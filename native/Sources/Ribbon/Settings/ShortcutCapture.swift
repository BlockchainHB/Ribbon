import AppKit
import Carbon
import RibbonCore
import SwiftUI

/// A first responder inside the recording sheet. It never installs a global event tap.
struct ShortcutCapture: NSViewRepresentable {
  let displayValue: String
  let onChord: (ShortcutChord) -> Void
  let onModifiers: (ShortcutModifiers) -> Void
  let cancel: () -> Void
  let confirm: () -> Void
  func makeNSView(context: Context) -> CaptureField { CaptureField() }
  func updateNSView(_ view: CaptureField, context: Context) {
    view.stringValue = displayValue
    view.placeholderString = "Press shortcut"
    view.isEditable = false
    view.isSelectable = false
    view.isBezeled = true
    view.bezelStyle = .roundedBezel
    view.alignment = .center
    view.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    view.onChord = onChord
    view.onModifiers = onModifiers
    view.cancel = cancel
    view.confirm = confirm
  }
  final class CaptureField: NSTextField {
    var onChord: ((ShortcutChord) -> Void)?
    var onModifiers: ((ShortcutModifiers) -> Void)?
    var cancel: (() -> Void)?
    var confirm: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      setAccessibilityElement(true)
      setAccessibilityRole(.textField)
      setAccessibilityHelp(
        "Press a shortcut combination. Escape cancels. Return saves a valid shortcut.")
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.window?.makeFirstResponder(self)
      }
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func flagsChanged(with event: NSEvent) { onModifiers?(Self.modifiers(event)) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
      guard window?.firstResponder === self else { return false }
      keyDown(with: event)
      return true
    }
    override func keyDown(with event: NSEvent) {
      guard !event.isARepeat else { return }
      let modifiers = Self.modifiers(event)
      if event.keyCode == 48 && (modifiers.isEmpty || modifiers == .shift) {
        if modifiers == .shift {
          window?.selectPreviousKeyView(self)
        } else {
          window?.selectNextKeyView(self)
        }
        return
      }
      if modifiers.isEmpty {
        switch event.keyCode {
        case 53:
          cancel?()
          return
        case 36:
          confirm?()
          return
        default: break
        }
      }
      let chord = ShortcutChord(Int(event.keyCode), modifiers: modifiers)
      setAccessibilityValue(ShortcutDisplay.accessible(chord))
      onChord?(chord)
    }
    static func modifiers(_ event: NSEvent) -> ShortcutModifiers {
      var value: ShortcutModifiers = []
      let flags = event.modifierFlags
      if flags.contains(.control) { value.insert(.control) }
      if flags.contains(.option) { value.insert(.option) }
      if flags.contains(.shift) { value.insert(.shift) }
      if flags.contains(.command) { value.insert(.command) }
      // Match Paneru's standalone Fn mask exactly. Navigation and function
      // keys can carry the general Function flag without Fn being held.
      if event.cgEvent?.flags.rawValue == 0x0080_0100 { value.insert(.function) }
      return value
    }
  }
}

enum ShortcutDisplay {
  static func string(_ chord: ShortcutChord) -> String {
    chord.modifiers.symbols + key(chord.keyCode)
  }
  static func accessible(_ chord: ShortcutChord) -> String {
    let names: [(ShortcutModifiers, String)] = [
      (.control, "Control"), (.option, "Option"), (.shift, "Shift"), (.command, "Command"),
      (.function, "Function"),
    ]
    return (names.filter { chord.modifiers.contains($0.0) }.map(\.1) + [key(chord.keyCode)]).joined(
      separator: " ")
  }
  static func key(_ code: Int) -> String {
    let named: [Int: String] = [
      36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 71: "⌧", 76: "⌤", 115: "↖", 116: "⇞",
      117: "⌦", 119: "↘", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
    if let name = named[code] { return name }
    let function: [Int: Int] = [
      122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9, 109: 10, 103: 11, 111: 12,
      105: 13, 107: 14, 113: 15, 106: 16, 64: 17, 79: 18, 80: 19, 90: 20,
    ]
    if let number = function[code] { return "F\(number)" }
    guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
      let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return "Key \(code)" }
    let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
    let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(
      to: UCKeyboardLayout.self)
    var state: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 8)
    let result = UCKeyTranslate(
      layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
      UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &state, 8, &length,
      &characters)
    guard result == noErr, length > 0 else { return "Key \(code)" }
    return String(utf16CodeUnits: characters, count: length).uppercased()
  }
}
