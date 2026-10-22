import AppKit
import RibbonCore

extension DesktopVerification {
  /// Native geometry, not a mock: hidden content must be outside every display.
  static func verifyParking(
    _ controller: SessionController, fixture: URL, displayID: UInt32, report: inout Report
  ) async throws {
    let beforeParking = try await settledFrames(fixture)
    for command: EngineCommand in [.first, .right, .right, .right, .fullWidth] {
      await controller.send(command)
      _ = try await settledFrames(fixture)
    }
    let parked = try await settledFrames(fixture)
    let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
    let hidden = state.windows.filter { $0.displayID == displayID && $0.visible == false }
    try await controller.query().write(
      to: fixture.deletingLastPathComponent().appendingPathComponent(
        "parking-state-\(displayID).json"))
    report.frames["parking-attempt-\(displayID)"] = parked
    try require(!hidden.isEmpty, "Scrolling produces hidden tiles on display \(displayID)")
    report.frames["parked-\(displayID)"] = parked
    try JSONEncoder().encode(parked).write(
      to: fixture.deletingLastPathComponent().appendingPathComponent("parked-\(displayID).json"))
    if CommandLine.arguments.contains("--qa-capture-parking") {
      try await Task.sleep(for: .seconds(2))
    }
    let top = NSScreen.screens.first!.frame.maxY
    for tile in hidden {
      guard let frame = parked.first(where: { Int32($0.id) == tile.windowID }) else {
        throw VerificationError.failed("Hidden native window is missing")
      }
      let rect = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
      for screen in NSScreen.screens {
        let full = screen.frame
        let bounds = CGRect(
          x: full.minX, y: top - full.maxY, width: full.width, height: full.height)
        let intersection = rect.intersection(bounds)
        try require(
          intersection.isNull || (intersection.width <= 1.1 && intersection.height <= 33),
          "Hidden tile \(tile.windowID) exposes \(intersection) on \(screen.localizedName)")
      }
    }
    let target = hidden[0]
    let old = beforeParking.first { Int32($0.id) == target.windowID }!
    DistributedNotificationCenter.default().postNotificationName(
      NSNotification.Name("dev.ribbon.fixture.focus-window"), object: nil,
      userInfo: ["id": Int(target.windowID)], deliverImmediately: true)
    try await eventually("External activation reveals the original monitor's hidden tile") {
      let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
      guard let tile = state.windows.first(where: { $0.windowID == target.windowID }),
        let actual = try frames(fixture).first(where: { Int32($0.id) == target.windowID })
      else { return false }
      return state.active.focusedWindowID == target.windowID && tile.visible == true
        && tile.displayID == displayID && actual.screenID == displayID && actual.focused
    }
    let revealed = try await settledFrames(fixture)
    let actual = revealed.first { Int32($0.id) == target.windowID }!
    try require(
      abs(actual.width - old.width) < 2 && abs(actual.height - old.height) < 2,
      "Hidden tile reveal preserves its native size")
    report.frames["revealed-\(displayID)"] = revealed
    report.checks.append(
      Check(name: "compact parking and external reveal on display \(displayID)", passed: true))
  }
}
