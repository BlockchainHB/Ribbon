import AppKit
import RibbonCore

extension DesktopVerification {
  /// Real native windows and engine responses. The engine remains fixture-only.
  static func verifyPairing(
    _ controller: SessionController, fixture: URL, report: inout Report
  ) async throws {
    let initial = try await overviewState(controller)
    let rows = initial.displays.filter { $0.columns.count >= 3 }
    for display in rows {
      let left = display.columns[0].id
      let right = display.columns[1].id
      let other = display.columns.last!.id
      try await overviewCommand(controller, ["focusid", String(left)])
      _ = try await settledFrames(fixture)
      let before = try frames(fixture)
      try await overviewCommand(controller, ["pairid", String(left), "east"])
      try await eventually("Native pair has one shared engine identity") {
        let state = try await overviewState(controller)
        guard let cols = state.columns(containing: left),
          let a = cols.first(where: { $0.contains(left) }),
          let b = cols.first(where: { $0.contains(right) })
        else { return false }
        return a.pairID != nil && a.pairID == b.pairID
      }
      let paired = try await settledFrames(fixture)
      try require(
        before.filter { [UInt32(left), UInt32(right)].contains($0.id) }.allSatisfy { old in
          paired.contains { $0.id == old.id && abs($0.width - old.width) < 2 }
        }, "Pairing preserves native widths")
      report.checks.append(
        Check(name: "pairing preserves widths on display \(display.id)", passed: true))

      for ratio in ["third", "half", "twothirds", "third"] {
        try await overviewCommand(controller, ["pairfitid", String(right), ratio])
        _ = try await settledFrames(fixture)
        try verifyPairFrames(
          fixture, left: left, right: right, display: display.id, gap: controller.settings.gap)
      }
      let expected = try frames(fixture).filter { [UInt32(left), UInt32(right)].contains($0.id) }
      for id in [right, left, right, left] {
        try await overviewCommand(controller, ["focusid", String(id)])
        try await eventually("Native pair member receives focus") {
          try frames(fixture).contains { $0.id == UInt32(id) && $0.focused }
        }
        let current = try await settledFrames(fixture)
        try require(
          expected.allSatisfy { old in current.contains { $0.id == old.id && old.matches($0) } },
          "Internal focus leaves pair stationary")
      }
      report.frames["pair-thirds-\(display.id)"] = try frames(fixture)
      report.checks.append(
        Check(
          name: "three pair ratios fit actual native windows; internal focus stays still",
          passed: true))

      try await overviewCommand(controller, ["reorder", String(right), String(other), "after"])
      try await eventually("Moving right member carries left member in engine order") {
        let state = try await overviewState(controller)
        guard let cols = state.columns(containing: left),
          let a = cols.firstIndex(where: { $0.contains(left) }),
          let b = cols.firstIndex(where: { $0.contains(right) }),
          let c = cols.firstIndex(where: { $0.contains(other) })
        else { return false }
        return a == c + 1 && b == a + 1 && cols[a].pairID == cols[b].pairID
      }
      _ = try await settledFrames(fixture)
      report.checks.append(Check(name: "reorder moves a complete native pair", passed: true))

      try await overviewCommand(controller, ["focusid", String(other)])
      await controller.send(.fullWidth)
      _ = try await settledFrames(fixture)
      try await eventually("Both pair members are genuinely hidden") {
        let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
        return [left, right].allSatisfy { id in
          state.windows.contains { $0.windowID == id && $0.visible == false }
        }
      }
      // No Ribbon focus command: this activates the real application and its
      // requested window, exercising the route launcher quicklinks depend on.
      DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("dev.ribbon.fixture.focus-window"), object: nil,
        userInfo: ["id": Int(right)], deliverImmediately: true)
      try await eventually("Application activation reveals both hidden pair members") {
        let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
        return state.active.focusedWindowID == right
          && [left, right].allSatisfy { id in
            state.windows.contains { $0.windowID == id && $0.visible == true }
          }
      }
      _ = try await settledFrames(fixture)
      try verifyPairFrames(
        fixture, left: left, right: right, display: display.id, gap: controller.settings.gap)
      report.checks.append(
        Check(
          name: "real app activation reveals a hidden pair and focuses the requested member",
          passed: true))

      let beforeUngrouped = try frames(fixture)
      // Capture the actual overview in both appearances, including pair badges.
      try await overviewCommand(controller, ["overview"])
      try await eventually("Pair overview is visible") { overviewButton(left) != nil }
      for dark in [false, true] {
        for window in NSApp.windows where window.title == "Arrange Windows" {
          window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        }
        try await Task.sleep(for: .milliseconds(300))
        try await captureOverview(
          fixture: fixture, name: "pair-overview-\(dark ? "dark" : "light").png")
      }
      if CommandLine.arguments.contains("--qa-external-input") {
        let directory = fixture.deletingLastPathComponent()
        let point = try requirePoint(left, trailing: false)
        try JSONSerialization.data(withJSONObject: ["x": point.x, "y": point.y])
          .write(to: directory.appendingPathComponent("pair-menu-request.json"), options: .atomic)
        try await eventually("External native pairing menu exercised") {
          FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("pair-menu-result.json").path)
        }
        let result =
          try JSONSerialization.jsonObject(
            with: Data(contentsOf: directory.appendingPathComponent("pair-menu-result.json")))
          as? [String: Any]
        try require(
          result?["ungrouped"] as? Bool == true, "Native context menu Ungroup action works")
        report.checks.append(
          Check(name: "native overview pairing menu and Ungroup action", passed: true))
      } else {
        try await overviewCommand(controller, ["unpairid", String(left)])
      }
      try await eventually("Ungroup clears engine membership") {
        let cols = try await overviewState(controller).columns(containing: left) ?? []
        return cols.filter { $0.contains(left) || $0.contains(right) }.allSatisfy {
          $0.pairID == nil
        }
      }
      if NSApp.windows.contains(where: { $0.title == "Arrange Windows" && $0.isVisible }) {
        try await overviewCommand(controller, ["overview"])
      }
      _ = try await settledFrames(fixture)
      let afterUngrouped = try frames(fixture)
      try require(
        beforeUngrouped.filter { [UInt32(left), UInt32(right)].contains($0.id) }.allSatisfy { old in
          afterUngrouped.contains { $0.id == old.id && old.matches($0) }
        }, "Ungroup leaves native geometry intact")
      try await overviewCommand(controller, ["pairfitid", String(left), "half"])
      _ = try await settledFrames(fixture)
      try verifyPairFrames(
        fixture, left: left, right: right, display: display.id, gap: controller.settings.gap)
      report.checks.append(
        Check(name: "independent arrangement works without pair membership", passed: true))
    }
  }

  private static func verifyPairFrames(
    _ fixture: URL, left: Int32, right: Int32, display: UInt32, gap: Int
  ) throws {
    let current = try frames(fixture)
    guard let a = current.first(where: { $0.id == UInt32(left) }),
      let b = current.first(where: { $0.id == UInt32(right) }),
      let screen = NSScreen.screens.first(where: {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
          == display
      })
    else { throw VerificationError.failed("Pair native frames missing") }
    let viewport = screen.visibleFrame
    try require(abs(a.x - viewport.minX - Double(gap)) < 2, "Pair starts at usable left margin")
    try require(abs(b.x + b.width - viewport.maxX + Double(gap)) < 2, "Pair fills usable width")
    try require(
      abs(b.x - a.x - a.width - Double(gap)) < 2, "Pair keeps internal gap without overlap")
    try require(a.screenID == display && b.screenID == display, "Pair stays on its owning display")
  }
}
