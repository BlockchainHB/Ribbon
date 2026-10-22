import AppKit
import RibbonCore
import XCTest

@testable import Ribbon

final class ShortcutCaptureTests: XCTestCase {
  @MainActor
  func testRecorderKeepsFirstResponderForCommandCombinations() throws {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 100),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let field = ShortcutCapture.CaptureField(frame: NSRect(x: 10, y: 10, width: 300, height: 28))
    field.isEditable = false
    field.isSelectable = false
    window.contentView?.addSubview(field)
    XCTAssertTrue(window.makeFirstResponder(field))
    XCTAssertTrue(
      window.firstResponder === field, "The recorder must bypass the text field editor.")
    var captured: ShortcutChord?
    field.onChord = { captured = $0 }
    let key = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.control, .option, .command],
        timestamp: 0, windowNumber: window.windowNumber, context: nil,
        characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40))
    XCTAssertTrue(field.performKeyEquivalent(with: key))
    XCTAssertEqual(captured, ShortcutChord(40, modifiers: [.control, .option, .command]))
  }

  @MainActor
  func testEscapeAndReturnUseRecorderActionsWithoutCreatingBindings() throws {
    let field = ShortcutCapture.CaptureField()
    var cancelled = false
    var confirmed = false
    var chords: [ShortcutChord] = []
    field.cancel = { cancelled = true }
    field.confirm = { confirmed = true }
    field.onChord = { chords.append($0) }
    for code: UInt16 in [53, 36] {
      let key = try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
          isARepeat: false, keyCode: code))
      field.keyDown(with: key)
    }
    XCTAssertTrue(cancelled)
    XCTAssertTrue(confirmed)
    XCTAssertTrue(chords.isEmpty)
  }
}
