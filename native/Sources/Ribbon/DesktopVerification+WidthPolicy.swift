import AppKit
import RibbonCore

extension DesktopVerification {
  /// Disposable native resize requests exercise engine policy, not Swift layout state.
  static func verifyWidthPolicy(
    _ controller: SessionController, fixture: URL, report: inout Report
  ) async throws {
    let initial = try await settledFrames(fixture)
    for window in initial {
      DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("dev.ribbon.fixture.focus-window"), object: nil,
        userInfo: ["id": Int(window.id)], deliverImmediately: true)
      try await eventually("Reveal the owned fixture before its native resize") {
        let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
        return state.active.focusedWindowID == Int32(window.id)
          && state.windows.contains { $0.windowID == Int32(window.id) && $0.visible == true }
      }
      _ = try await settledFrames(fixture)
      DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("dev.ribbon.fixture.resize-window"), object: nil,
        userInfo: ["id": Int(window.id), "width": 300.0], deliverImmediately: true)
      try await eventually("Native fixture accepts its preferred width") {
        try frames(fixture).contains { $0.id == window.id && abs($0.width - 300) < 2 }
      }
      _ = try await settledFrames(fixture)
    }
    try await eventually("Fixture resize establishes preferred widths") {
      try frames(fixture).allSatisfy { abs($0.width - 300) < 2 }
    }
    _ = try await settledFrames(fixture)
    let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
    let owners = Dictionary(
      uniqueKeysWithValues: state.windows.compactMap { window in
        window.displayID.map { (UInt32(window.windowID), $0) }
      })
    let top = NSScreen.screens.first!.frame.maxY
    let gap = Double(controller.settings.gap)
    for round in 0..<2 {
      controller.settings.widthPolicy = .fill
      controller.saveSettings()
      try await eventually("Fill occupies each physical monitor independently") {
        let current = try frames(fixture)
        return NSScreen.screens.allSatisfy { screen in
          let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber)
            .uint32Value
          let windows = current.filter { owners[$0.id] == id }.sorted { $0.x < $1.x }
          guard let first = windows.first, let last = windows.last else { return false }
          let viewport = screen.visibleFrame
          return windows.allSatisfy { $0.width > 300 && $0.screenID == id }
            && abs(first.x - viewport.minX - gap) < 2
            && abs(last.x + last.width - viewport.maxX + gap) < 2
            && windows.allSatisfy { abs($0.y - (top - viewport.maxY)) < 2 }
            && zip(windows, windows.dropFirst()).allSatisfy {
              abs($1.x - ($0.x + $0.width) - gap) < 2
            }
        }
      }
      report.frames["filled-\(round)"] = try await settledFrames(fixture)
      if round == 0 && CommandLine.arguments.contains("--qa-capture-widths") {
        try Data("ready".utf8).write(
          to: fixture.deletingLastPathComponent().appendingPathComponent("fill-ready.txt"))
        try await Task.sleep(for: .seconds(3))
      }
      controller.settings.widthPolicy = .preserve
      controller.saveSettings()
      try await eventually("Preserve restores every preferred width") {
        try frames(fixture).allSatisfy { abs($0.width - 300) < 2 }
      }
      report.frames["preserved-\(round)"] = try await settledFrames(fixture)
    }
    report.checks.append(
      Check(name: "fill uses both monitors with native gaps and no spill", passed: true))
    report.checks.append(
      Check(name: "two live policy round trips restore preferred widths", passed: true))
  }
}
