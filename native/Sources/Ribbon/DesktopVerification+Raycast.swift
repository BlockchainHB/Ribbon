import AppKit
import RibbonCore

extension DesktopVerification {
  /// Human/tool-driven Raycast Quicklink, with an owned fixture and explicit readiness receipts.
  static func verifyRaycastOpening(
    _ controller: SessionController, fixture: URL, original: [FixtureFrame],
    owned: inout [NSRunningApplication], report: inout Report
  ) async throws {
    let directory = fixture.deletingLastPathComponent()
    for displayID in Set(original.map(\.screenID)).sorted() {
      let target = original.first { $0.screenID == displayID }!
      DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("dev.ribbon.fixture.focus-window"), object: nil,
        userInfo: ["id": Int(target.id)], deliverImmediately: true)
      try await eventually("Primary fixture target receives focus") {
        let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
        return state.active.focusedWindowID == Int32(target.id)
      }
      _ = try await settledFrames(fixture)
      let baseline = try JSONDecoder().decode(EngineState.self, from: await controller.query())
        .windows.count
      let secondaryReport = directory.appendingPathComponent("raycast-secondary-\(displayID).json")
      let config = NSWorkspace.OpenConfiguration()
      config.activates = true
      config.createsNewApplicationInstance = true
      config.arguments = ["--report", secondaryReport.path, "--display", String(displayID)]
      let app = try await NSWorkspace.shared.openApplication(
        at: controller.fixtureURL, configuration: config)
      owned.append(app)
      try await eventually("Secondary fixture joins the selected display") {
        let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
        return (try? frames(secondaryReport).count) == 4 && state.windows.count == baseline + 4
      }
      let secondaryFrames = try await settledFrames(secondaryReport)
      guard let secondaryTarget = secondaryFrames.last else {
        throw VerificationError.failed("Secondary fixture has no native windows")
      }
      DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("dev.ribbon.fixture.focus-window"), object: nil,
        userInfo: ["id": Int(secondaryTarget.id)], deliverImmediately: true)
      try await eventually("Secondary fixture owns native and engine focus") {
        let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
        let focused = try frames(secondaryReport).contains {
          $0.id == secondaryTarget.id && $0.focused
        }
        return state.active.focusedWindowID == Int32(secondaryTarget.id)
          && focused
      }
      await controller.send(.fullWidth)
      _ = try await settledFrames(fixture)
      _ = try await settledFrames(secondaryReport)
      let parkedState = try JSONDecoder().decode(EngineState.self, from: await controller.query())
      try require(
        parkedState.windows.contains {
          $0.windowID == Int32(target.id) && $0.displayID == displayID && $0.visible == false
        },
        "Quicklink's existing target is hidden on its original display")
      let before = try frames(fixture)
      report.frames["raycast-before-\(displayID)"] = before
      let ready: [String: Any] = [
        "displayID": displayID, "targetWindowID": target.id,
        "quicklink": "Ribbon Parking QA", "fixturePath": controller.fixtureURL.path,
      ]
      try JSONSerialization.data(withJSONObject: ready, options: [.prettyPrinted, .sortedKeys])
        .write(
          to: directory.appendingPathComponent("raycast-ready-\(displayID).json"))
      let deadline = ProcessInfo.processInfo.systemUptime + 90
      var sawRaycast = false
      var revealed = false
      while ProcessInfo.processInfo.systemUptime < deadline {
        sawRaycast =
          sawRaycast
          || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.raycast.macos"
        let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
        if sawRaycast, state.active.focusedWindowID == Int32(target.id),
          state.windows.contains(where: {
            $0.windowID == Int32(target.id) && $0.displayID == displayID && $0.visible == true
          }),
          try frames(fixture).contains(where: {
            $0.id == target.id && $0.screenID == displayID && $0.focused
          })
        {
          revealed = true
          break
        }
        try await Task.sleep(for: .milliseconds(100))
      }
      try require(
        revealed, "Actual Raycast Quicklink reveals hidden target on display \(displayID)")
      report.frames["raycast-after-\(displayID)"] = try await settledFrames(fixture)
      report.checks.append(
        Check(
          name: "actual Raycast Quicklink reveals hidden tile on display \(displayID)", passed: true
        ))
      try Data("passed".utf8).write(
        to: directory.appendingPathComponent("raycast-passed-\(displayID).txt"))
      app.terminate()
      try await eventually("Owned secondary fixture exits") { app.isTerminated }
    }
  }
}
