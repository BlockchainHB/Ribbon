import AppKit
import RibbonCore

extension DesktopVerification {
  static func verifyMaximizedStartup(
    _ controller: SessionController, fixture: URL, original: [FixtureFrame], report: inout Report
  ) async throws {
    for old in original {
      guard
        let screen = NSScreen.screens.first(where: {
          ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            == old.screenID
        })
      else { throw VerificationError.failed("Fixture monitor is missing") }
      try require(
        abs(old.width - screen.visibleFrame.width) <= 8,
        "Startup fixture begins maximized on its own monitor")
      DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("dev.ribbon.fixture.focus-window"), object: nil,
        userInfo: ["id": Int(old.id)], deliverImmediately: true)
      try await eventually("External activation reveals a maximized startup tile") {
        let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
        let current = try frames(fixture)
        return state.active.focusedWindowID == Int32(old.id)
          && state.windows.contains {
            $0.windowID == Int32(old.id) && $0.visible == true && $0.displayID == old.screenID
          }
          && current.contains { $0.id == old.id && $0.focused }
      }
      let settled = try await settledFrames(fixture)
      guard let actual = settled.first(where: { $0.id == old.id }) else {
        throw VerificationError.failed("Activated fixture is missing")
      }
      let usable = screen.visibleFrame
      let top = NSScreen.screens.first!.frame.maxY
      try require(
        actual.screenID == old.screenID && actual.x >= usable.minX - 2
          && actual.x + actual.width <= usable.maxX + 2
          && actual.y >= top - usable.maxY - 2
          && actual.y + actual.height <= top - usable.minY + 2,
        "Maximized startup tile is visible inside its original monitor")
      report.frames["startup-revealed-\(old.id)"] = settled
    }
    report.checks.append(
      Check(
        name: "every maximized startup tile can be revealed on its original display", passed: true))
  }
}
