import AppKit
import RibbonCore

extension DesktopVerification {
  /// Hardware checks use the fixture's own NSWindow reports, plus engine ownership.
  static func verifyDual(
    _ controller: SessionController, fixture: URL, original: [FixtureFrame], report: inout Report
  ) async throws {
    let groups = Dictionary(grouping: original, by: \.screenID)
    try require(
      groups.count == 2 && groups.values.allSatisfy { $0.count == 4 },
      "Four real fixture windows opened on each display")
    let tiled = try await settledFrames(fixture)
    report.frames["dualInitial"] = tiled
    try await verifyOwnership(controller, fixture: fixture, expected: original)
    report.checks.append(Check(name: "independent strips on both physical displays", passed: true))

    for group in groups.values {
      try await focusFixture(group[0].id, fixture: fixture, controller: controller)
      let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
      let ordered = state.windows.filter { $0.displayID == group[0].screenID }
      try require(ordered.count == 4, "Selected monitor retains four columns")
      await controller.send(.first)
      try await waitForFocus(UInt32(ordered[0].windowID), fixture: fixture, controller: controller)
      let before = try await settledFrames(fixture)
      await controller.send(.right)
      try await waitForFocus(UInt32(ordered[1].windowID), fixture: fixture, controller: controller)
      let navigated = try await settledFrames(fixture)
      report.frames["beforeNavigation-\(group[0].screenID)"] = before
      report.frames["afterNavigation-\(group[0].screenID)"] = navigated
      try require(
        before.first(where: \.focused)?.id != navigated.first(where: \.focused)?.id,
        "Navigation changes focus on the selected monitor")
      let other = before.filter { $0.screenID != group[0].screenID }
      try require(
        other.allSatisfy { old in navigated.contains { $0.id == old.id && $0.matches(old) } },
        "Navigation on one monitor leaves the other strip unchanged")
      await controller.send(.fullWidth)
      let resized = try await settledFrames(fixture)
      let focused = resized.first(where: \.focused)!
      let screen = NSScreen.screens.first {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
          == focused.screenID
      }!
      try require(
        abs(focused.width - (screen.visibleFrame.width - Double(controller.settings.gap * 2))) < 4,
        "Full-width uses the selected monitor's usable width")
      try require(
        abs(focused.height - (screen.visibleFrame.height - Double(controller.settings.gap * 2)))
          < 4,
        "Focused column uses its own monitor's usable height")
      try await focusFixture(group.last!.id, fixture: fixture, controller: controller)
      let overflow = try await settledFrames(fixture)
      report.frames["overflow-\(group[0].screenID)"] = overflow
      try await verifyOwnership(controller, fixture: fixture, expected: original)
      try require(
        other.allSatisfy { old in overflow.contains { $0.id == old.id && $0.matches(old) } },
        "Overflow and full-width changes leave the other display unchanged")
    }
    report.checks.append(
      Check(name: "navigation and overflow do not move the other monitor's windows", passed: true))

    let source = original[0]
    try await focusFixture(source.id, fixture: fixture, controller: controller)
    await controller.send(.width)
    let beforeMove = try await settledFrames(fixture)
    let moving = beforeMove.first { $0.id == source.id }!
    let screenWidths = Dictionary(
      uniqueKeysWithValues: NSScreen.screens.map {
        (
          ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value,
          $0.visibleFrame.width - Double(controller.settings.gap * 2)
        )
      })
    let targetID = groups.keys.first { $0 != source.screenID }!
    for _ in 0..<3 {
      await controller.send(.nextDisplay)
      try await eventually("Window transferred to the second monitor") {
        try frames(fixture).contains { $0.id == source.id && $0.screenID == targetID && $0.focused }
      }
      let transferred = try await settledFrames(fixture)
      let moved = transferred.first { $0.id == source.id }!
      let expectedWidth = moving.width / screenWidths[source.screenID]! * screenWidths[targetID]!
      try require(
        abs(moved.width - expectedWidth) < 4,
        "Transfer preserves the width proportion on a differently sized display")
      try require(
        beforeMove.filter { $0.id != source.id }.allSatisfy { old in
          transferred.contains { $0.id == old.id && abs($0.width - old.width) < 4 }
        }, "Transfer preserves the other windows' widths")
      await controller.send(.nextDisplay)
      try await eventually("Window transferred back to its original monitor") {
        try frames(fixture).contains {
          $0.id == source.id && $0.screenID == source.screenID && $0.focused
        }
      }
      let returned = try await settledFrames(fixture)
      try require(
        abs(returned.first { $0.id == source.id }!.width - moving.width) < 4,
        "Round-trip display transfer preserves width")
    }
    try await verifyOwnership(controller, fixture: fixture, expected: original)
    report.frames["dualAfterTransfers"] = try await settledFrames(fixture)
    report.checks.append(
      Check(
        name: "six physical display transfers preserve proportions and other widths", passed: true))
    let beforeNew = try await settledFrames(fixture)
    DistributedNotificationCenter.default().postNotificationName(
      NSNotification.Name("dev.ribbon.fixture.add-window"), object: nil, userInfo: nil,
      deliverImmediately: true)
    try await eventually("Ninth fixture enters its own display strip") {
      let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
      let count = try frames(fixture).count
      return state.windows.count == 9 && count == 9
    }
    let afterNew = try await settledFrames(fixture)
    let added = afterNew.first { new in !beforeNew.contains { $0.id == new.id } }!
    try require(added.screenID == targetID, "New window stays on the display where it opened")
    try await verifyOwnership(controller, fixture: fixture, expected: original)
    try require(
      beforeNew.allSatisfy { old in
        afterNew.contains {
          $0.id == old.id && abs($0.width - old.width) < 4
            && (old.screenID == added.screenID || $0.matches(old))
        }
      }, "Opening on one display preserves widths and the other strip's positions")
    report.checks.append(
      Check(name: "opening a window preserves both monitors' existing widths", passed: true))
  }

  private static func focusFixture(_ id: UInt32, fixture: URL, controller: SessionController)
    async throws
  {
    DistributedNotificationCenter.default().postNotificationName(
      NSNotification.Name("dev.ribbon.fixture.focus-window"), object: nil,
      userInfo: ["id": Int(id)], deliverImmediately: true)
    try await waitForFocus(id, fixture: fixture, controller: controller)
    _ = try await settledFrames(fixture)
    try await waitForFocus(id, fixture: fixture, controller: controller)
  }

  private static func waitForFocus(_ id: UInt32, fixture: URL, controller: SessionController)
    async throws
  {
    do {
      try await eventually("Fixture receives focus") {
        let nativeFocused = try frames(fixture).contains { $0.id == id && $0.focused }
        let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
        return nativeFocused && state.active.focusedWindowID == Int32(id)
      }
    } catch {
      try Data(contentsOf: fixture).write(
        to: fixture.deletingLastPathComponent().appendingPathComponent("focus-failure-fixture.json")
      )
      let stateData = try await controller.query()
      try stateData.write(
        to: fixture.deletingLastPathComponent().appendingPathComponent("focus-failure-engine.json"))
      let state = try JSONDecoder().decode(EngineState.self, from: stateData)
      let actual = try frames(fixture).first(where: \.focused)?.id
      throw VerificationError.failed(
        "Expected focus \(id); native \(String(describing: actual)), engine \(String(describing: state.active.focusedWindowID))"
      )
    }
  }

  private static func verifyOwnership(
    _ controller: SessionController, fixture: URL, expected: [FixtureFrame]
  ) async throws {
    let actual = try frames(fixture)
    let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
    try require(
      expected.allSatisfy { old in
        actual.contains { $0.id == old.id && $0.screenID == old.screenID }
          && state.windows.contains {
            $0.windowID == Int32(old.id) && $0.displayID == old.screenID && !$0.floating
          }
      }, "Every window retains its original display without an explicit transfer")
  }
}
