import AppKit
import RibbonCore
import XCTest

@testable import Ribbon

final class RibbonStatusMenuTests: XCTestCase {
  @MainActor
  func testMenuContainsActionsBeforeTheFirstNativeClick() {
    _ = NSApplication.shared
    let controller = SessionController(
      store: LocalStore(
        directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    )
    let owner = RibbonStatusMenu(controller: controller, openSettings: {})
    XCTAssertFalse(owner.menu.items.isEmpty)
    XCTAssertTrue(owner.menu.items.contains { $0.title == "Settings…" && $0.isEnabled })
    XCTAssertEqual(owner.menu.items.last?.title, "Quit Ribbon")
  }

  func testWindowCommandsRequireRunningManagedAppAndDisplayActionsRequireTwoScreens() {
    for action in RibbonMenuAction.allCases {
      XCTAssertFalse(action.isEnabled(phase: .stopped, managedFrontmost: true, displayCount: 2))
      XCTAssertFalse(action.isEnabled(phase: .starting, managedFrontmost: true, displayCount: 2))
      XCTAssertFalse(action.isEnabled(phase: .running, managedFrontmost: false, displayCount: 2))
      XCTAssertTrue(action.isEnabled(phase: .running, managedFrontmost: true, displayCount: 2))
      XCTAssertEqual(
        action.isEnabled(phase: .running, managedFrontmost: true, displayCount: 1),
        !action.needsMultipleDisplays)
    }
    XCTAssertEqual(EngineCommand.sendDisplay.arguments, ["send-cmd", "window", "nextdisplaysend"])
    XCTAssertEqual(EngineCommand.fit.arguments, ["send-cmd", "window", "snap"])
  }

  @MainActor
  func testMenuRefreshesCustomShortcutsAndReleasesThemWhenClosed() throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let controller = SessionController(store: LocalStore(directory: directory))
    try controller.settings.setShortcuts(
      [ShortcutChord(0, modifiers: [.control, .command])], for: .width)
    let owner = RibbonStatusMenu(controller: controller, openSettings: {})
    owner.menuWillOpen(owner.menu)
    let width = try XCTUnwrap(
      owner.menu.items.first { ($0.representedObject as? RibbonMenuAction) == .width })
    XCTAssertEqual(width.keyEquivalent, "a")
    XCTAssertEqual(width.keyEquivalentModifierMask, [.control, .command])
    XCTAssertFalse(width.isEnabled)
    XCTAssertNil(owner.menu.items.first?.view, "Menu rows must use AppKit's native layout.")
    owner.menuDidClose(owner.menu)
    XCTAssertEqual(width.keyEquivalent, "")
    XCTAssertTrue(width.keyEquivalentModifierMask.isEmpty)

    try controller.settings.setShortcuts([ShortcutChord(14)], for: .width)
    owner.menuWillOpen(owner.menu)
    let refreshed = try XCTUnwrap(
      owner.menu.items.first { ($0.representedObject as? RibbonMenuAction) == .width })
    XCTAssertEqual(refreshed.keyEquivalent, "e")
    let preferences = try XCTUnwrap(owner.menu.items.first { $0.title == "Settings…" })
    XCTAssertTrue(preferences.isEnabled)
    XCTAssertEqual(preferences.keyEquivalent, ",")
    XCTAssertEqual(preferences.keyEquivalentModifierMask, .command)
    XCTAssertEqual(owner.menu.items.last?.title, "Quit Ribbon")
  }

  @MainActor
  func testFunctionKeyCustomizationUsesNativeMenuKeyEquivalent() throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let controller = SessionController(store: LocalStore(directory: directory))
    try controller.settings.setShortcuts([ShortcutChord(96, modifiers: [])], for: .width)
    let owner = RibbonStatusMenu(controller: controller, openSettings: {})
    owner.menuWillOpen(owner.menu)
    let width = try XCTUnwrap(
      owner.menu.items.first { ($0.representedObject as? RibbonMenuAction) == .width })
    XCTAssertEqual(width.keyEquivalent, "\u{f708}")
    XCTAssertTrue(width.keyEquivalentModifierMask.isEmpty)
  }
}
