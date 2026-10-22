import AppKit
import Combine
import RibbonCore

/// Native menu rows; each action delegates to the engine's existing command API.
enum RibbonMenuAction: String, CaseIterable {
  case left, right, up, down, first, width, center, fit, fullWidth, stack, unstack, tabs,
    float, nextDisplay, sendDisplay

  var command: EngineCommand { EngineCommand(rawValue: rawValue)! }
  var shortcut: ShortcutAction {
    switch self {
    case .left: .focusLeft
    case .right: .focusRight
    case .up: .focusUp
    case .down: .focusDown
    case .first: .focusFirst
    case .width: .width
    case .center: .center
    case .fit: .fit
    case .fullWidth: .fullWidth
    case .stack: .stack
    case .unstack: .unstack
    case .tabs: .tabs
    case .float: .float
    case .nextDisplay: .nextDisplay
    case .sendDisplay: .sendDisplay
    }
  }
  var title: String {
    switch self {
    case .left: "Focus Left"
    case .right: "Focus Right"
    case .up: "Focus Above"
    case .down: "Focus Below"
    case .first: "Focus First Column"
    case .width: "Cycle Column Width"
    case .center: "Center Column"
    case .fit: "Fit in Display"
    case .fullWidth: "Toggle Full Width"
    case .stack: "Stack Window"
    case .unstack: "Unstack Window"
    case .tabs: "Toggle Stack Tabs"
    case .float: "Toggle Floating Window"
    case .nextDisplay: "Move to Next Display"
    case .sendDisplay: "Send to Next Display"
    }
  }
  var symbol: String {
    switch self {
    case .left: "arrow.left"
    case .right: "arrow.right"
    case .up: "arrow.up"
    case .down: "arrow.down"
    case .first: "arrow.left.to.line"
    case .width: "arrow.left.and.right"
    case .center: "rectangle.center.inset.filled"
    case .fit: "arrow.up.left.and.arrow.down.right"
    case .fullWidth: "rectangle"
    case .stack: "rectangle.stack"
    case .unstack: "rectangle.stack.badge.minus"
    case .tabs: "rectangle.topthird.inset.filled"
    case .float: "rectangle.on.rectangle"
    case .nextDisplay: "display.2"
    case .sendDisplay: "arrow.right.square"
    }
  }
  func isEnabled(phase: SessionPhase, managedFrontmost: Bool, displayCount: Int) -> Bool {
    phase == .running && managedFrontmost
      && (!needsMultipleDisplays || displayCount > 1)
  }
  var needsMultipleDisplays: Bool { self == .nextDisplay || self == .sendDisplay }
}

@MainActor
final class RibbonStatusMenu: NSObject, NSMenuDelegate {
  let menu = NSMenu(title: "Ribbon")
  private let controller: SessionController
  private let openSettings: () -> Void
  private let openOverview: () -> Void
  private(set) var statusItem: NSStatusItem?
  private var observation: AnyCancellable?

  init(
    controller: SessionController, openOverview: @escaping () -> Void = {},
    openSettings: @escaping () -> Void
  ) {
    self.controller = controller
    self.openSettings = openSettings
    self.openOverview = openOverview
    super.init()
    menu.autoenablesItems = false
    menu.delegate = self
    // AppKit does not start tracking an empty status-item menu, so waiting
    // for menuWillOpen to supply its first rows leaves the icon inert.
    rebuild()
    menuDidClose(menu)  // Leave global engine chords unreserved until the menu actually opens.
  }

  func install() {
    guard statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.autosaveName = "Ribbon"
    item.button?.identifier = .init("dev.ribbon.status")
    item.button?.image =
      RibbonBrand.menuIcon
      ?? NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Ribbon")
    item.button?.setAccessibilityLabel("Ribbon")
    item.menu = menu
    // Visibility can be restored as false by AppKit/Control Center. This app
    // promises a menu bar control, so explicitly show its own item at launch.
    item.isVisible = true
    statusItem = item
    updateStatus()
    observation = controller.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
      self?.updateStatus()
    }
  }

  private func updateStatus() {
    statusItem?.button?.toolTip = "Ribbon — \(controller.phase.rawValue)"
    statusItem?.button?.setAccessibilityValue(controller.phase.rawValue)
  }

  func menuWillOpen(_ menu: NSMenu) {
    guard menu === self.menu else { return }
    rebuild()
  }

  func menuDidClose(_ menu: NSMenu) {
    guard menu === self.menu else { return }
    // Global engine bindings must not become app shortcuts while this menu is closed.
    for item in allItems(menu)
    where item.representedObject is RibbonMenuAction
      || item.identifier?.rawValue == "session"
      || item.identifier?.rawValue == "overview"
    {
      item.keyEquivalent = ""
      item.keyEquivalentModifierMask = []
    }
  }

  func rebuild() {
    menu.removeAllItems()
    let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    let managed = frontmost.map(controller.settings.manages) ?? false
    let displays = NSScreen.screens.count
    let overview = item("Arrange Windows…", action: #selector(arrangeWindows))
    overview.identifier = .init("overview")
    overview.image = symbol("square.grid.2x2")
    overview.isEnabled = controller.phase == .running
    applyShortcut(controller.settings.shortcuts(for: .overview).first, to: overview)
    menu.addItem(overview)
    menu.addItem(.separator())
    for action: RibbonMenuAction in [.left, .right] { add(action, to: menu, managed, displays) }
    menu.addItem(.separator())
    for action: RibbonMenuAction in [.width, .center, .fit, .fullWidth] {
      add(action, to: menu, managed, displays)
    }
    menu.addItem(.separator())
    addSubmenu("Focus", symbol: "viewfinder", actions: [.up, .down, .first], managed, displays)
    addSubmenu(
      "Stacks", symbol: "rectangle.stack", actions: [.stack, .unstack, .tabs], managed, displays)
    if displays > 1 {
      addSubmenu(
        "Displays", symbol: "display.2", actions: [.nextDisplay, .sendDisplay], managed, displays)
    }
    add(.float, to: menu, managed, displays)
    menu.addItem(.separator())

    let session: NSMenuItem
    if controller.phase == .stopped && !controller.permissionGranted {
      session = item("Allow Accessibility Access…", action: #selector(allowAccessibility))
    } else if controller.phase == .stopped && controller.recoveryPending {
      session = item("Restore Previous Window Positions", action: #selector(restore))
    } else if controller.phase == .stopped && !controller.settings.canManageApplications {
      session = item("Choose Applications…", action: #selector(settings))
    } else {
      let title = controller.phase == .running ? "Pause Ribbon" : controller.sessionButtonTitle
      session = item(title, action: #selector(toggleSession))
      session.isEnabled = controller.canToggleSession
      if controller.phase == .running {
        applyShortcut(controller.settings.shortcuts(for: .pause).first, to: session)
      }
    }
    session.identifier = NSUserInterfaceItemIdentifier("session")
    menu.addItem(session)
    let preferences = item("Settings…", action: #selector(settings))
    preferences.keyEquivalent = ","
    preferences.keyEquivalentModifierMask = .command
    menu.addItem(preferences)
    menu.addItem(item("About Ribbon", action: #selector(about)))
    menu.addItem(.separator())
    let quit = item("Quit Ribbon", action: #selector(quit))
    quit.keyEquivalent = "q"
    quit.keyEquivalentModifierMask = .command
    menu.addItem(quit)
  }

  private func add(
    _ action: RibbonMenuAction, to menu: NSMenu, _ managed: Bool, _ displays: Int
  ) {
    let row = item(action.title, action: #selector(performWindowAction(_:)))
    row.representedObject = action
    row.image = symbol(action.symbol)
    row.isEnabled = action.isEnabled(
      phase: controller.phase, managedFrontmost: managed, displayCount: displays)
    row.toolTip = action.shortcut.detail
    applyShortcut(controller.settings.shortcuts(for: action.shortcut).first, to: row)
    menu.addItem(row)
  }

  private func addSubmenu(
    _ title: String, symbol name: String, actions: [RibbonMenuAction], _ managed: Bool,
    _ displays: Int
  ) {
    let submenu = NSMenu(title: title)
    submenu.autoenablesItems = false
    for action in actions { add(action, to: submenu, managed, displays) }
    let row = item(title, action: nil)
    row.image = symbol(name)
    row.submenu = submenu
    row.isEnabled = submenu.items.contains(where: \.isEnabled)
    menu.addItem(row)
  }

  private func item(_ title: String, action: Selector?) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.isEnabled = true
    #if compiler(>=6.4)
      // This preference is declared by the macOS 27 SDK, not older SDKs.
      if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
    #endif
    return item
  }

  private func symbol(_ name: String) -> NSImage? {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    image?.isTemplate = true
    return image
  }

  private func allItems(_ menu: NSMenu) -> [NSMenuItem] {
    menu.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) }
  }

  private func applyShortcut(_ chord: ShortcutChord?, to item: NSMenuItem) {
    guard let chord else { return }
    let special: [Int: String] = [
      36: "\r", 48: "\t", 49: " ", 51: "\u{8}", 53: "\u{1b}",
      123: "\u{f702}", 124: "\u{f703}", 125: "\u{f701}", 126: "\u{f700}",
      71: "\u{f739}", 76: "\u{3}", 115: "\u{f729}", 116: "\u{f72c}",
      117: "\u{f728}", 119: "\u{f72b}", 121: "\u{f72d}",
    ]
    var key = special[chord.keyCode] ?? ShortcutDisplay.key(chord.keyCode).lowercased()
    if ShortcutChord.functionKeys.contains(chord.keyCode),
      let number = Int(key.dropFirst()), let scalar = UnicodeScalar(0xf704 + number - 1)
    {
      key = String(scalar)
    }
    guard key.count == 1 else { return }
    item.keyEquivalent = key
    var modifiers: NSEvent.ModifierFlags = []
    for (source, target): (ShortcutModifiers, NSEvent.ModifierFlags) in [
      (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
      (.function, .function),
    ] where chord.modifiers.contains(source) { modifiers.insert(target) }
    item.keyEquivalentModifierMask = modifiers
  }

  @objc private func performWindowAction(_ sender: NSMenuItem) {
    guard let action = sender.representedObject as? RibbonMenuAction else { return }
    Task { await controller.send(action.command) }
  }
  @objc private func settings() { openSettings() }
  @objc private func arrangeWindows() { openOverview() }
  @objc private func about() { showRibbonAbout() }
  @objc private func quit() { NSApp.terminate(nil) }
  @objc private func toggleSession() { Task { await controller.toggleSession() } }
  @objc private func restore() { Task { await controller.restorePreviousSession() } }
  @objc private func allowAccessibility() { controller.openPermissionSettings() }
}
