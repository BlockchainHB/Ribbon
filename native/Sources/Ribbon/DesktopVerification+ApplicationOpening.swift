import AppKit
import RibbonCore

extension DesktopVerification {
  /// Exercises launcher-style app opening using disposable, allowlisted processes only.
  static func verifyApplicationOpening(
    _ controller: SessionController, fixture: URL, owned: inout [NSRunningApplication],
    report: inout Report
  ) async throws {
    let baseline = try frames(fixture).count
    let secondaryReport = fixture.deletingLastPathComponent().appendingPathComponent(
      "launcher-frames.json")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.createsNewApplicationInstance = true
    configuration.arguments = ["--report", secondaryReport.path]
    let launched = try await NSWorkspace.shared.openApplication(
      at: controller.fixtureURL, configuration: configuration)
    owned.append(launched)
    try await eventually("New application windows join the existing strip") {
      let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
      return (try? frames(secondaryReport).count) == 4 && state.windows.count == baseline + 4
        && state.windows.allSatisfy { $0.bundleID == RibbonSettings.fixtureBundleID }
    }
    report.checks.append(
      Check(name: "launcher opens a new application into the tile set", passed: true))
    _ = try await settledFrames(secondaryReport)
    await controller.send(.first)
    _ = try await settledFrames(fixture)
    // The second process retains its last key window while another app owns focus.
    // Launchers use the same system activation path to bring an already open app forward.
    NSApp.activate(ignoringOtherApps: true)
    try await eventually("Disposable launcher owns activation") { NSApp.isActive }
    NSApp.yieldActivation(to: launched)
    try require(
      launched.activate(from: .current, options: [.activateIgnoringOtherApps]),
      "macOS accepted the launcher activation request")
    try await eventually("Reopening a tiled application reveals its focused window") {
      guard let focused = try frames(secondaryReport).first(where: \.focused),
        let screen = NSScreen.screens.first(where: {
          ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            == focused.screenID
        })
      else { return false }
      let top = NSScreen.screens.first?.frame.maxY ?? 0
      let bounds = screen.visibleFrame
      let viewport = CGRect(
        x: bounds.minX, y: top - bounds.maxY, width: bounds.width, height: bounds.height)
      let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
      return state.active.focusedWindowID == Int32(exactly: focused.id)
        && focused.x >= viewport.minX - 2
        && focused.x + focused.width <= viewport.maxX + 2
        && focused.y >= viewport.minY - 2
        && focused.y + focused.height <= viewport.maxY + 2
    }
    report.checks.append(
      Check(name: "launcher activation focuses and reveals an existing tiled app", passed: true))
    launched.terminate()
    try await eventually("Launcher fixture exits without removing the original tile set") {
      let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
      return launched.isTerminated && state.windows.count == baseline
    }
  }
}
