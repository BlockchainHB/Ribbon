import AppKit
import RibbonCore

extension DesktopVerification {
  struct MotionSample: Codable {
    let time: Double
    let frames: [FixtureFrame]
  }
  struct MotionObservation: Encodable {
    let displayID: UInt32
    let samples: Int
    let movingSamples: Int
    let minimumGap: Double
    let settledGap: Double
    let neighborSpillSamples: Int
  }

  /// Samples the fixture's own NSWindows during animation, separately from settled checks.
  static func verifyMotion(
    _ controller: SessionController, fixture: URL, report: inout Report
  ) async throws {
    // Closing the launcher fixture can leave macOS with no key window. Acquire
    // an owned window before issuing strip commands rather than assuming focus.
    if try !frames(fixture).contains(where: \.focused), let target = try frames(fixture).first {
      DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("dev.ribbon.fixture.focus-window"), object: nil,
        userInfo: ["id": Int(target.id)], deliverImmediately: true)
      try await eventually("Motion fixture receives native focus") {
        try frames(fixture).contains(where: \.focused)
      }
    }
    await controller.send(.first)
    _ = try await settledFrames(fixture)
    // A strip that already fits is correctly clamped at its left edge.
    // Give the scroll input a real overflow range on large external displays.
    await controller.send(.fullWidth)
    _ = try await settledFrames(fixture)
    let initial = try frames(fixture)
    guard let displayID = initial.first(where: \.focused)?.screenID else {
      throw VerificationError.failed("Motion fixture has no focused native window")
    }
    if let first = initial.first(where: \.focused) {
      let cursor = CGEvent(
        mouseEventSource: nil, mouseType: .mouseMoved,
        mouseCursorPosition: CGPoint(x: first.x + 100, y: first.y + 100), mouseButton: .left)
      cursor?.flags = []
      cursor?.post(tap: .cghidEventTap)
      for _ in 0..<8 {
        let scroll = CGEvent(
          scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
          wheel1: 0, wheel2: 1, wheel3: 0)
        scroll?.flags = CGEventFlags(
          rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | 0x21)
        scroll?.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(20))
      }
      try await eventually("Native modifier-scroll moves the fixture strip") {
        // Edge presentation can hold the visible origin at the viewport edge
        // while the body narrows. That is native scrolling too.
        try frames(fixture).contains {
          $0.id == first.id && (abs($0.x - first.x) > 10 || abs($0.width - first.width) > 10)
        }
      }
      report.checks.append(
        Check(name: "native modifier-scroll input moves the strip", passed: true))
      await controller.send(.first)
      _ = try await settledFrames(fixture)
    }
    let ownership = try JSONDecoder().decode(EngineState.self, from: await controller.query())
    let owners = Dictionary(
      uniqueKeysWithValues: ownership.windows.compactMap { tile -> (UInt32, UInt32)? in
        guard let id = UInt32(exactly: tile.windowID), let display = tile.displayID else {
          return nil
        }
        return (id, display)
      })
    let directory = fixture.deletingLastPathComponent()
    let capture = directory.appendingPathComponent("motion-frames.json")
    try? FileManager.default.removeItem(at: capture)
    DistributedNotificationCenter.default().postNotificationName(
      NSNotification.Name("dev.ribbon.fixture.motion"), object: "begin", deliverImmediately: true)
    try await Task.sleep(for: .milliseconds(100))
    for command: EngineCommand in [.right, .right, .left, .width, .fullWidth, .width, .first] {
      await controller.send(command)
      _ = try await settledFrames(fixture)
    }
    // Retarget before each transition finishes, including width changes and
    // reversals. These are actual engine commands against disposable windows.
    for command: EngineCommand in [.right, .right, .first, .width, .width, .fullWidth, .first] {
      await controller.send(command)
      try await Task.sleep(for: .milliseconds(65))
    }
    _ = try await settledFrames(fixture)
    // Restore the full-width stress target so the final gap measurement has
    // two actual visible neighbors rather than an undefined single-tile gap.
    await controller.send(.fullWidth)
    _ = try await settledFrames(fixture)
    report.checks.append(
      Check(name: "interrupted native movement and resizing settle", passed: true))
    DistributedNotificationCenter.default().postNotificationName(
      NSNotification.Name("dev.ribbon.fixture.motion"), object: "end", deliverImmediately: true)
    try await eventually("Motion frames recorded") {
      FileManager.default.fileExists(atPath: capture.path)
    }
    let data = try Data(contentsOf: capture)
    try data.write(to: directory.appendingPathComponent("motion-\(displayID).json"))
    let samples = try JSONDecoder().decode([MotionSample].self, from: data)
    try require(
      samples.count > 30 && samples.count < 1200, "Motion recording is bounded and populated")
    let screen = NSScreen.screens.first {
      ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        == displayID
    }!
    let top = NSScreen.screens.first!.frame.maxY
    let viewport = CGRect(
      x: screen.visibleFrame.minX, y: top - screen.visibleFrame.maxY,
      width: screen.visibleFrame.width, height: screen.visibleFrame.height)
    var minimumGap = Double.infinity
    var movingSamples = 0
    var neighborSpillSamples = 0
    for (index, sample) in samples.enumerated() {
      let spills = sample.frames.contains { frame in
        guard let owner = owners[frame.id] else { return false }
        let rect = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        return NSScreen.screens.contains { other in
          let id = (other.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
          guard id != owner else { return false }
          let bounds = CGRect(
            x: other.frame.minX, y: top - other.frame.maxY, width: other.frame.width,
            height: other.frame.height)
          let overlap = rect.intersection(bounds)
          // Compact parking permits a one-point outer edge. A body has
          // meaningful area on both axes, as in the standalone frame sampler.
          return !overlap.isNull && overlap.width > 1.1 && overlap.height > 1.1
        }
      }
      if spills { neighborSpillSamples += 1 }

      if index > 0
        && sample.frames.contains(where: { frame in
          samples[index - 1].frames.contains { old in
            old.id == frame.id
              && (abs(old.x - frame.x) > 1 || abs(old.width - frame.width) > 1)
          }
        })
      {
        movingSamples += 1
      }
      minimumGap = min(
        minimumGap, visibleGap(sample.frames, displayID: displayID, viewport: viewport))
    }
    let settledGap = visibleGap(samples.last!.frames, displayID: displayID, viewport: viewport)
    try require(
      movingSamples > 5 && minimumGap.isFinite && settledGap.isFinite,
      "Real tile movement was sampled")
    report.motion.append(
      MotionObservation(
        displayID: displayID, samples: samples.count, movingSamples: movingSamples,
        minimumGap: minimumGap, settledGap: settledGap, neighborSpillSamples: neighborSpillSamples))
    try require(
      neighborSpillSamples == 0,
      "Window body flashed on a neighboring monitor in \(neighborSpillSamples) motion samples")
    try require(minimumGap >= 0, "Moving tiles overlap by \(-minimumGap) points")
    try require(
      abs(settledGap - Double(controller.settings.windowPadding * 2)) <= 1,
      "Settled tiles retain the configured gap")
    report.checks.append(
      Check(name: "moving tiles remain separated on display \(displayID)", passed: true))
  }

  private static func visibleGap(_ frames: [FixtureFrame], displayID: UInt32, viewport: CGRect)
    -> Double
  {
    // Hidden edge slivers intentionally share a parking position. Measure content tiles
    // with most of their area on this display, including partially visible columns.
    let visible = frames.filter { frame in
      let rect = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
      let area = rect.intersection(viewport)
      return frame.screenID == displayID && area.width * area.height > rect.width * rect.height / 2
    }.sorted { $0.x < $1.x }
    return zip(visible, visible.dropFirst()).map { left, right in
      right.x - (left.x + left.width)
    }.min() ?? .infinity
  }
}
