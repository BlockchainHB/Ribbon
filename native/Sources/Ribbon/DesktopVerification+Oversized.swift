import AppKit
import RibbonCore

extension DesktopVerification {
  static func verifyOversizedFocus(
    _ controller: SessionController, fixture: URL, report: inout Report
  ) async throws {
    let initial = try await settledFrames(fixture)
    try await Task.sleep(for: .milliseconds(500))
    let oversized = initial.filter { frame in
      guard
        let screen = NSScreen.screens.first(where: {
          ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            == frame.screenID
        })
      else { return false }
      return (frame.minimumWidth ?? 0) > screen.visibleFrame.width
    }
    try require(
      oversized.count == NSScreen.screens.count, "One oversized native minimum exists per display")
    for target in oversized {
      guard
        let previous = initial.first(where: { $0.screenID == target.screenID && $0.id != target.id }
        )
      else {
        throw VerificationError.failed("Normal focus control missing")
      }
      try await overviewCommand(controller, ["focusid", String(previous.id)])
      try await eventually("Normal control receives native focus") {
        try frames(fixture).contains { $0.id == previous.id && $0.focused }
      }
      try await overviewCommand(controller, ["focusid", String(target.id)])
      try await eventually("Oversized projected window receives real native focus") {
        let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
        let current = try frames(fixture)
        return state.active.focusedWindowID == Int32(target.id)
          && NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            == RibbonSettings.fixtureBundleID
          && current.contains { $0.id == target.id && $0.focused && $0.screenID == target.screenID }
      }
      let focused = try frames(fixture).first { $0.id == target.id }!
      try require(
        focused.width >= target.minimumWidth!, "Native minimum is never squeezed for focus")
      for _ in 0..<10 {
        try await Task.sleep(for: .milliseconds(50))
        guard let held = try frames(fixture).first(where: { $0.id == target.id }) else {
          throw VerificationError.failed("Oversized fixture disappeared")
        }
        try require(
          held.focused && held.width == focused.width && held.height == focused.height
            && held.screenID == target.screenID, "Oversized focus remains stable on its owner")
      }
      report.frames["oversized-\(target.screenID)"] = try frames(fixture)
      report.checks.append(
        Check(
          name: "oversized native minimum receives stable focus on display \(target.screenID)",
          passed: true))
    }
  }
}
