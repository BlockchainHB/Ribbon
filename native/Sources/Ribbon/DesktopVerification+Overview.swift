import AppKit
import ApplicationServices
import RibbonCore

extension DesktopVerification {
  static func overviewState(_ controller: SessionController) async throws -> OverviewSnapshot {
    let result = try await CommandRunner().run(
      controller.engineURL, arguments: ["overview-state"],
      environment: controller.engineEnvironment,
      timeout: 2)
    try require(result.status == 0, "Overview query succeeded")
    return try JSONDecoder().decode(OverviewSnapshot.self, from: Data(result.output.utf8))
  }

  static func overviewCommand(_ controller: SessionController, _ arguments: [String]) async throws {
    let result = try await CommandRunner().run(
      controller.engineURL, arguments: ["send-cmd", "window"] + arguments,
      environment: controller.engineEnvironment, timeout: 2)
    try require(result.status == 0, "Overview command delivered")
  }

  static func verifyOverview(
    _ controller: SessionController, fixture: URL, report: inout Report
  ) async throws {
    let initial = try await overviewState(controller)
    let rows = initial.displays.filter { !$0.columns.isEmpty }
    try require(rows.count == NSScreen.screens.count, "Overview includes each connected display")
    try require(
      rows.flatMap(\.columns).flatMap(\.windows).allSatisfy {
        $0.bundleID == RibbonSettings.fixtureBundleID
      }, "Overview stays in fixture scope")
    report.checks.append(
      Check(name: "overview includes all connected strips and hidden tiles", passed: true))
    for display in rows {
      let last = display.columns.last!.id
      try await overviewCommand(controller, ["focusid", String(last)])
      try await eventually("Last fixture focused for overflow setup") {
        try frames(fixture).contains { $0.id == UInt32(last) && $0.focused }
      }
      await controller.send(.fullWidth)
      _ = try await settledFrames(fixture)
      try await overviewCommand(controller, ["focusid", String(display.columns[0].id)])
      try await eventually("Fixture focused before overview shortcut") {
        try frames(fixture).contains { $0.id == UInt32(display.columns[0].id) && $0.focused }
      }
      try await Task.sleep(for: .seconds(1))
      try await eventually("Last tile is genuinely offscreen") {
        let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
        return state.windows.first { $0.windowID == last }?.visible == false
      }
      let down = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true)
      down?.flags = CGEventFlags(
        rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | 0x21)
      down?.post(tap: .cghidEventTap)
      let up = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: false)
      up?.flags = []
      up?.post(tap: .cghidEventTap)
      try await eventually("Overview panel visible") {
        NSApp.windows.contains { $0.title == "Arrange Windows" && $0.isVisible }
      }
      let source = display.columns[0].id
      let target = display.columns[2].id
      try await eventually("Overview buttons exposed to accessibility") {
        overviewButton(source) != nil && overviewButton(target) != nil
      }
      let from = try requirePoint(source, trailing: false)
      let to = try requirePoint(target, trailing: true)
      try await captureOverview(fixture: fixture, name: "before-drag-\(display.id).png")
      await overviewDrag(from: from, to: to)
      try await captureOverview(fixture: fixture, name: "after-drag-\(display.id).png")
      try await eventually("Native drag changes the engine's order") {
        let state = try await overviewState(controller)
        guard let cols = state.columns(containing: source),
          let a = cols.firstIndex(where: { $0.contains(source) }),
          let b = cols.firstIndex(where: { $0.contains(target) })
        else { return false }
        return a == b + 1
      }
      report.checks.append(
        Check(name: "native icon drag inserts column on display \(display.id)", passed: true))
      try await eventually("Dragged tile is selected") { selectedOverviewID(source) }
      key(123)
      try await eventually("Arrow key selects the preceding icon") { selectedOverviewID(target) }
      key(36)
      try await eventually("Return focuses the selected tile") {
        try frames(fixture).contains { $0.id == UInt32(target) && $0.focused }
          && !NSApp.windows.contains { $0.title == "Arrange Windows" && $0.isVisible }
      }
      report.checks.append(Check(name: "native overview arrow and Return navigation", passed: true))
      try await overviewCommand(controller, ["overview"])
      try await eventually("Overview reopened") {
        NSApp.windows.contains { $0.title == "Arrange Windows" && $0.isVisible && $0.isKeyWindow }
          && overviewButton(last) != nil
      }
      try await Task.sleep(for: .milliseconds(250))
      let point = try requirePoint(display.columns.last!.id, trailing: false)
      mouse(.leftMouseDown, at: point)
      mouse(.leftMouseUp, at: point)
      try await eventually("Click reveals and focuses hidden native tile") {
        try frames(fixture).contains { $0.id == UInt32(display.columns.last!.id) && $0.focused }
          && !NSApp.windows.contains { $0.title == "Arrange Windows" && $0.isVisible }
      }
      let full = try await settledFrames(fixture).first { $0.focused }!
      let screen = NSScreen.screens.first {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
          == display.id
      }!
      let top = NSScreen.screens.first!.frame.maxY - screen.visibleFrame.maxY
      try require(
        abs(full.y - top) <= 1 && abs(full.height - screen.visibleFrame.height) <= 1,
        "Full-width tile touches usable top and bottom edges")
      try require(
        abs(full.width - screen.visibleFrame.width + Double(controller.settings.gap * 2)) <= 1,
        "Full-width tile retains horizontal spacing")
      report.frames["full-height-\(display.id)"] = try frames(fixture)
      report.checks.append(
        Check(
          name: "full usable height without vertical outer gaps on display \(display.id)",
          passed: true))
      await controller.send(.fullWidth)
      _ = try await settledFrames(fixture)
      await controller.send(.stack)
      try await eventually("Stack formed") {
        try await overviewState(controller).displays.flatMap(\.columns).contains {
          $0.windows.count == 2
        }
      }
      let stacked = try await overviewState(controller).displays.first { $0.id == display.id }!
        .columns.first { $0.windows.count == 2 }!
      let ids = Set(stacked.windows.map { UInt32($0.id) })
      let pair = try await settledFrames(fixture).filter { ids.contains($0.id) }.sorted {
        $0.y < $1.y
      }
      try require(
        pair.count == 2 && abs(pair[0].y - top) <= 1
          && abs(pair[1].y + pair[1].height - top - screen.visibleFrame.height) <= 1
          && abs(pair[1].y - pair[0].y - pair[0].height - Double(controller.settings.gap)) <= 1,
        "Stack keeps only its internal vertical gap")
      report.frames["stack-\(display.id)"] = try frames(fixture)
      report.checks.append(
        Check(
          name: "stack retains internal gap and flush outer edges on display \(display.id)",
          passed: true))
      await controller.send(.unstack)
    }
    // Leave a real overview visible briefly for native light/dark captures.
    try await overviewCommand(controller, ["overview"])
    try await eventually("Overview ready for visual review") {
      NSApp.windows.contains { $0.title == "Arrange Windows" && $0.isVisible }
    }
    for dark in [false, true] {
      for window in NSApp.windows where window.title == "Arrange Windows" {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      }
      try await Task.sleep(for: .milliseconds(500))
      try await captureOverview(
        fixture: fixture, name: dark ? "overview-dark.png" : "overview-light.png")
    }
    try await overviewCommand(controller, ["overview"])
  }

  private static func selectedOverviewID(_ id: Int32) -> Bool {
    guard let node = overviewButton(id) else { return false }
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(node, kAXValueAttribute as CFString, &value)
    return value as? String == "Selected"
  }

  private static func key(_ code: CGKeyCode) {
    for down in [true, false] {
      let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
      event?.flags = []
      event?.post(tap: .cghidEventTap)
    }
  }

  static func captureOverview(fixture: URL, name: String) async throws {
    guard let window = NSApp.windows.first(where: { $0.title == "Arrange Windows" && $0.isVisible })
    else { throw VerificationError.failed("Overview disappeared before its visual capture") }
    let directory = fixture.deletingLastPathComponent()
    let destination = directory.appendingPathComponent(name)
    if CommandLine.arguments.contains("--qa-external-capture") {
      // The external, user-authorized macOS screenshot tool owns capture
      // permission. Ribbon itself needs only Accessibility to manage windows.
      let request = directory.appendingPathComponent("capture-request.json")
      let data = try JSONSerialization.data(withJSONObject: [
        "window": window.windowNumber, "path": destination.path,
      ])
      try data.write(to: request, options: .atomic)
      defer { try? FileManager.default.removeItem(at: request) }
      try await eventually("External native window capture completed") {
        FileManager.default.fileExists(atPath: destination.path)
      }
    } else {
      let result = try await CommandRunner().run(
        URL(fileURLWithPath: "/usr/sbin/screencapture"),
        arguments: ["-x", "-l", String(window.windowNumber), destination.path])
      try require(result.status == 0, "Native overview screenshot command succeeded")
    }
    let image = try Data(contentsOf: destination)
    try require(!image.isEmpty, "Native overview screenshot exists")
  }

  static func overviewButton(_ id: Int32) -> AXUIElement? {
    func attr(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
      var value: CFTypeRef?
      AXUIElementCopyAttributeValue(node, key as CFString, &value)
      return value
    }
    func find(_ node: AXUIElement) -> AXUIElement? {
      if attr(node, "AXIdentifier") as? String == "ribbon.column.\(id)" { return node }
      for child in attr(node, "AXChildren") as? [AXUIElement] ?? [] {
        if let found = find(child) { return found }
      }
      return nil
    }
    return find(AXUIElementCreateApplication(getpid()))
  }

  static func requirePoint(_ id: Int32, trailing: Bool) throws -> CGPoint {
    guard let node = overviewButton(id) else {
      throw VerificationError.failed("Missing overview button")
    }
    var origin: CFTypeRef?
    var size: CFTypeRef?
    AXUIElementCopyAttributeValue(node, kAXPositionAttribute as CFString, &origin)
    AXUIElementCopyAttributeValue(node, kAXSizeAttribute as CFString, &size)
    guard let origin, let size else { throw VerificationError.failed("Missing button frame") }
    var p = CGPoint.zero
    var s = CGSize.zero
    AXValueGetValue(origin as! AXValue, .cgPoint, &p)
    AXValueGetValue(size as! AXValue, .cgSize, &s)
    return CGPoint(x: p.x + (trailing ? s.width - 12 : s.width / 2), y: p.y + s.height / 2)
  }

  private static func mouse(_ type: CGEventType, at point: CGPoint) {
    let event = CGEvent(
      mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
    event?.flags = []
    event?.setIntegerValueField(.mouseEventClickState, value: 1)
    event?.post(tap: .cghidEventTap)
  }

  private static func overviewDrag(from: CGPoint, to: CGPoint) async {
    mouse(.mouseMoved, at: from)
    mouse(.leftMouseDown, at: from)
    try? await Task.sleep(for: .milliseconds(150))
    for step in 1...30 {
      let t = Double(step) / 30
      mouse(
        .leftMouseDragged,
        at: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
      try? await Task.sleep(for: .milliseconds(25))
    }
    mouse(.leftMouseUp, at: to)
  }
}
