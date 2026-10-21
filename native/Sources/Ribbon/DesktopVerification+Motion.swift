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
  }

  /// Samples the fixture's own NSWindows during animation, separately from settled checks.
  static func verifyMotion(
    _ controller: SessionController, fixture: URL, report: inout Report
  ) async throws {
    await controller.send(.first)
    _ = try await settledFrames(fixture)
    let initial = try frames(fixture)
    let displayID = initial.first(where: \.focused)!.screenID
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
    for (index, sample) in samples.enumerated() {
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
        minimumGap: minimumGap, settledGap: settledGap))
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
