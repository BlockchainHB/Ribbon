import AppKit
import ApplicationServices

extension DesktopVerification {
  /// Exercise the actual SwiftUI switch. Calling controller.pause() cannot
  /// detect a disabled control, which was the build 14 regression.
  static func clickSessionSwitch(_ controller: SessionController, running: Bool) async throws {
    guard let window = NSApp.windows.first(where: { $0.title == "General" && $0.canBecomeMain })
    else { throw VerificationError.failed("General window missing for switch check") }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    try await Task.sleep(for: .milliseconds(200))
    let root = AXUIElementCreateApplication(getpid())
    func attr(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
      var value: CFTypeRef?
      AXUIElementCopyAttributeValue(node, key as CFString, &value)
      return value
    }
    func find(_ node: AXUIElement) -> AXUIElement? {
      if attr(node, kAXDescriptionAttribute) as? String == "Enable Ribbon" { return node }
      for child in attr(node, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let found = find(child) { return found }
      }
      return nil
    }
    guard let control = find(root),
      (attr(control, kAXEnabledAttribute) as? NSNumber)?.boolValue == true,
      let origin = attr(control, kAXPositionAttribute), let size = attr(control, kAXSizeAttribute)
    else { throw VerificationError.failed("Window management switch is missing or disabled") }
    var p = CGPoint.zero
    var s = CGSize.zero
    AXValueGetValue(origin as! AXValue, .cgPoint, &p)
    AXValueGetValue(size as! AXValue, .cgSize, &s)
    let point = CGPoint(x: p.x + s.width / 2, y: p.y + s.height / 2)
    if CommandLine.arguments.contains("--qa-maximized-startup"),
      CommandLine.arguments.contains("--qa-external-input"),
      let index = CommandLine.arguments.firstIndex(of: "--qa-output")
    {
      let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        .deletingLastPathComponent()
      let request = directory.appendingPathComponent("switch-request-\(UUID().uuidString).json")
      try JSONSerialization.data(withJSONObject: ["running": running]).write(
        to: request, options: .atomic)
      defer { try? FileManager.default.removeItem(at: request) }
      try await eventually("External accessibility switch activation") {
        controller.phase == (running ? .running : .stopped)
      }
      return
    }
    controlClick(point)
    try await eventually(running ? "Native switch starts Ribbon" : "Native switch pauses Ribbon") {
      controller.phase == (running ? .running : .stopped)
    }
  }

  static func verifyStatusItem(_ owner: RibbonStatusMenu?, report: inout Report) async throws {
    guard let owner, let item = owner.statusItem, item.isVisible,
      let button = item.button, button.image != nil,
      owner.menu.items.contains(where: { $0.title == "Settings…" && $0.isEnabled })
    else { throw VerificationError.failed("Ribbon status item or populated menu is missing") }
    guard CommandLine.arguments.contains("--qa-external-input"),
      let index = CommandLine.arguments.firstIndex(of: "--qa-output")
    else {
      throw VerificationError.failed("Native menu verification requires the external AX driver")
    }
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
      .deletingLastPathComponent()
    let request = directory.appendingPathComponent("menu-check-request.json")
    let response = directory.appendingPathComponent("menu-check-result.json")
    try Data("{}".utf8).write(to: request, options: .atomic)
    defer { try? FileManager.default.removeItem(at: request) }
    // Control Center hosts the status item. Its external accessibility tree
    // reports the actual hit target; AppKit's proxy frame can still be stale.
    try await eventually("External native menu bar check completed") {
      FileManager.default.fileExists(atPath: response.path)
    }
    let result =
      try JSONSerialization.jsonObject(with: Data(contentsOf: response)) as? [String: Bool]
    try require(
      result?["opened"] == true && result?["settings"] == true && result?["closed"] == true,
      "External accessibility click opens and closes the populated Ribbon menu")
    report.checks.append(
      Check(
        name: "visible menu bar icon opens populated native menu and closes with Escape",
        passed: true))
  }

  private static func controlClick(_ point: CGPoint) {
    for type: CGEventType in [.leftMouseDown, .leftMouseUp] {
      let event = CGEvent(
        mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
      event?.flags = []
      event?.setIntegerValueField(.mouseEventClickState, value: 1)
      event?.post(tap: .cghidEventTap)
    }
  }
}
