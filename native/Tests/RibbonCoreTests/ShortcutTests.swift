import Foundation
import XCTest

@testable import RibbonCore

final class ShortcutTests: XCTestCase {
  func testLegacySettingsMigrateToAutomaticManagementAndKeepShortcuts() throws {
    let data = Data(
      #"{"scope":"selected","selectedBundleIDs":["com.apple.Safari"],"gap":18,"animationSpeed":14,"centerFocused":true,"gestureFingers":0}"#
        .utf8)
    let settings = try JSONDecoder().decode(RibbonSettings.self, from: data).validated()
    XCTAssertEqual(settings.scope, .all)
    XCTAssertEqual(settings.selectedBundleIDs, ["com.apple.Safari"])
    XCTAssertTrue(settings.manages("com.example.NewApp"))
    XCTAssertEqual(settings.gap, 18)
    XCTAssertEqual(settings.shortcuts(for: .focusRight), [ShortcutChord(124)])
    XCTAssertEqual(settings.scrollModifiers, [.control, .option])
  }
  func testCustomMultipleAndDisabledBindingsSurviveRoundTripAndReachEngine() throws {
    var settings = RibbonSettings()
    try settings.setShortcuts(
      [ShortcutChord(40), ShortcutChord(14, modifiers: [.control, .command])], for: .focusRight)
    try settings.setShortcuts([], for: .pause)
    let restored = try JSONDecoder().decode(
      RibbonSettings.self, from: JSONEncoder().encode(settings)
    ).validated()
    XCTAssertEqual(restored, settings)
    let config = try restored.engineConfiguration()
    XCTAssertTrue(
      config.contains(
        "window_focus_east = [\"ctrl + alt - keycode:40\", \"ctrl + cmd - keycode:14\"]"))
    XCTAssertTrue(config.contains("quit = []"))
    XCTAssertFalse(config.contains("window_focus_east = [\"ctrl + alt - keycode:124\"]"))
  }
  func testConflictsAndInvalidKeysCannotPartiallyChangeSettings() throws {
    var settings = RibbonSettings()
    let original = settings
    XCTAssertThrowsError(try settings.setShortcuts([ShortcutChord(123)], for: .focusRight))
    XCTAssertEqual(settings, original)
    XCTAssertThrowsError(
      try settings.setShortcuts([ShortcutChord(12, modifiers: .command)], for: .focusRight))
    XCTAssertThrowsError(try settings.setShortcuts([ShortcutChord(999)], for: .focusRight))
    XCTAssertThrowsError(
      try settings.setShortcuts([ShortcutChord(0, modifiers: .shift)], for: .focusRight))
    XCTAssertThrowsError(
      try settings.setShortcuts(
        [ShortcutChord(0, modifiers: [.function, .command])], for: .focusRight))
    XCTAssertThrowsError(
      try settings.setShortcuts([ShortcutChord(40), ShortcutChord(40)], for: .focusRight))
    XCTAssertThrowsError(
      try settings.setShortcuts(
        [ShortcutChord(0), ShortcutChord(1), ShortcutChord(2), ShortcutChord(5)], for: .focusRight))
    XCTAssertEqual(settings, original)
    XCTAssertNoThrow(
      try settings.setShortcuts([ShortcutChord(122, modifiers: [])], for: .focusFirst))
  }
  func testUnknownActionsAndEmptyScrollModifierFailClosed() throws {
    var settings = RibbonSettings()
    settings.shortcutOverrides["restart"] = [ShortcutChord(0)]
    XCTAssertThrowsError(try settings.validated())
    settings = RibbonSettings()
    settings.scrollModifiers = []
    XCTAssertThrowsError(try settings.engineConfiguration())
  }
  func testDefaultsAreConflictFreeAndEveryActionIsRepresented() throws {
    let settings = RibbonSettings()
    XCTAssertNoThrow(try settings.validated())
    for action in ShortcutAction.allCases {
      XCTAssertTrue(try settings.engineConfiguration().contains(action.rawValue + " = ["))
    }
  }
  func testReduceMotionUsesInstantEngineMovementWithoutChangingPreference() throws {
    var settings = RibbonSettings()
    settings.animationSpeed = 18
    XCTAssertTrue(
      try settings.engineConfiguration(reduceMotion: true).contains("animation_speed = 1000000"))
    XCTAssertTrue(try settings.engineConfiguration().contains("animation_speed = 18"))
  }
}
