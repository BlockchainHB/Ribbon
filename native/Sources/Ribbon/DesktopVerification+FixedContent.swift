import AppKit
import RibbonCore

extension DesktopVerification {
  /// Native app frame sampling is separate from compositor/pixel verification.
  static func verifyFixedContent(
    _ controller: SessionController, fixture: URL, report: inout Report
  ) async throws {
    let original = try await settledFrames(fixture)
    // Session readiness reports scope before asynchronous native attachment and
    // the initial focus commit finish. Start external activation after that fence.
    try await Task.sleep(for: .milliseconds(500))
    let displays = Set(original.map(\.screenID)).sorted()
    for display in displays {
      for target in original.filter({ $0.screenID == display }).prefix(2) {
        DistributedNotificationCenter.default().postNotificationName(
          NSNotification.Name("dev.ribbon.fixture.focus-window"), object: nil,
          userInfo: ["id": Int(target.id)], deliverImmediately: true)
        try await eventually("Fixture activation reveals its owner display") {
          let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
          let current = try frames(fixture)
          return state.active.focusedWindowID == Int32(target.id)
            && current.contains {
              $0.id == target.id && $0.focused && $0.screenID == display
            }
        }
        await controller.send(.fullWidth)
        try await Task.sleep(for: .milliseconds(800))
      }
      let baseline = try await settledFrames(fixture)
      let directory = fixture.deletingLastPathComponent()
      let motion = directory.appendingPathComponent("motion-frames.json")
      try? FileManager.default.removeItem(at: motion)
      DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("dev.ribbon.fixture.motion"), object: "begin", deliverImmediately: true)
      if let focused = baseline.first(where: \.focused) {
        let before = try JSONDecoder().decode(EngineState.self, from: await controller.query())
          .windows.first(where: { $0.windowID == Int32(focused.id) })?.frame?.x
        let cursor = CGEvent(
          mouseEventSource: nil, mouseType: .mouseMoved,
          mouseCursorPosition: CGPoint(x: focused.x + 100, y: focused.y + 100), mouseButton: .left)
        cursor?.flags = []
        cursor?.post(tap: .cghidEventTap)
        for _ in 0..<8 {
          let scroll = CGEvent(
            scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
            wheel1: 0, wheel2: 1, wheel3: 0)
          scroll?.flags = CGEventFlags(
            rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | 0x21
          )
          scroll?.post(tap: .cghidEventTap)
          try await Task.sleep(for: .milliseconds(20))
        }
        try await eventually("Native modifier scroll changes logical strip position") {
          let current = try JSONDecoder().decode(EngineState.self, from: await controller.query())
            .windows.first(where: { $0.windowID == Int32(focused.id) })?.frame?.x
          return before != nil && current != nil && abs(current! - before!) > 10
        }
      }
      for command: EngineCommand in [.first, .right, .right, .left, .first, .right, .left, .first] {
        await controller.send(command)
        try await Task.sleep(for: .milliseconds(350))
      }
      try await Task.sleep(for: .milliseconds(500))
      DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("dev.ribbon.fixture.motion"), object: "end", deliverImmediately: true)
      try await eventually("Native frame samples were written") {
        FileManager.default.fileExists(atPath: motion.path)
      }
      let data = try Data(contentsOf: motion)
      try data.write(to: directory.appendingPathComponent("fixed-content-\(display).json"))
      let samples = try JSONDecoder().decode([MotionSample].self, from: data)
      try require(samples.count >= 30, "Fixed-content recording has native samples")
      for sample in samples {
        for actual in sample.frames {
          guard let before = baseline.first(where: { $0.id == actual.id }) else {
            throw VerificationError.failed("Unexpected fixture window in recording")
          }
          try require(
            abs(actual.width - before.width) < 1 && abs(actual.height - before.height) < 1,
            "Navigation changed native content size for \(actual.id): \(before.width)x\(before.height) -> \(actual.width)x\(actual.height)"
          )
          try require(
            actual.screenID == before.screenID, "Native anchor migrated to a neighboring display")
        }
      }
      await controller.send(.first)
      try await Task.sleep(for: .milliseconds(700))
      let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
      let padding = Double(controller.settings.windowPadding)
      let clientFrames = try frames(fixture)
      var geometry: [[String: Any]] = []
      for tile in state.windows {
        guard let logical = tile.frame,
          let client = clientFrames.first(where: { Int32($0.id) == tile.windowID }),
          let info =
            (CGWindowListCopyWindowInfo(.optionIncludingWindow, UInt32(tile.windowID))
            as? [[String: Any]])?.first,
          let values = info[kCGWindowBounds as String] as? [String: Any],
          let physical = CGRect(dictionaryRepresentation: values as CFDictionary)
        else { throw VerificationError.failed("Independent fixture bounds are missing") }
        let expected = CGRect(
          x: logical.x + padding, y: logical.y + padding,
          width: client.width, height: client.height)
        geometry.append([
          "id": tile.windowID, "expected": NSStringFromRect(expected),
          "physical": NSStringFromRect(physical),
        ])
        try require(
          abs(physical.minX - expected.minX) < 1 && abs(physical.minY - expected.minY) < 1
            && abs(physical.width - expected.width) < 1
            && abs(physical.height - expected.height) < 1,
          "Public WindowServer bounds must match the engine's full-width presentation for \(tile.windowID): \(physical) vs \(expected)"
        )
      }
      try JSONSerialization.data(withJSONObject: geometry, options: .prettyPrinted).write(
        to: fixture.deletingLastPathComponent().appendingPathComponent(
          "public-projection-\(display).json"))
      guard let focused = state.active.focusedWindowID,
        let native = try frames(fixture).first(where: { Int32($0.id) == focused }),
        let info =
          (CGWindowListCopyWindowInfo(.optionIncludingWindow, native.id) as? [[String: Any]])?
          .first,
        let values = info[kCGWindowBounds as String] as? [String: Any],
        let physical = CGRect(dictionaryRepresentation: values as CFDictionary)
      else { throw VerificationError.failed("Focused fixture geometry unavailable") }
      try require(
        abs(physical.minX - native.x) < 1 && abs(physical.minY - native.y) < 1,
        "Fully visible focus must restore ordinary native coordinates")
      report.frames["fixed-content-\(display)"] = try frames(fixture)
      report.checks.append(
        Check(
          name: "fixed native content through navigation and focus on display \(display)",
          passed: true))
      let beforeResize = try frames(fixture)
      for command: EngineCommand in [.width, .fullWidth, .width] {
        await controller.send(command)
        try await Task.sleep(for: .milliseconds(65))
      }
      try await Task.sleep(for: .milliseconds(800))
      let resized = try await settledFrames(fixture)
      for before in beforeResize {
        guard let after = resized.first(where: { $0.id == before.id }) else {
          throw VerificationError.failed("Fixture disappeared during interrupted resize")
        }
        try require(abs(before.height - after.height) < 1, "Width resize preserves native height")
        if Int32(before.id) != focused {
          try require(
            abs(before.width - after.width) < 1,
            "Width resize preserves every other window's content width")
        }
      }
      report.checks.append(
        Check(
          name: "interrupted width changes preserve neighboring content on display \(display)",
          passed: true))
    }
  }
}
