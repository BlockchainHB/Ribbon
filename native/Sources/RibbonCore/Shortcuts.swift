import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let control = Self(rawValue: 1)
  public static let option = Self(rawValue: 2)
  public static let shift = Self(rawValue: 4)
  public static let command = Self(rawValue: 8)
  public static let function = Self(rawValue: 16)
  public static let all: Self = [.control, .option, .shift, .command, .function]
  public var engineValue: String {
    [
      (Self.control, "ctrl"), (.option, "alt"), (.shift, "shift"), (.command, "cmd"),
      (.function, "fn"),
    ]
    .filter { contains($0.0) }.map(\.1).joined(separator: " + ")
  }
  public var symbols: String {
    [(Self.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"), (.function, "fn ")]
      .filter { contains($0.0) }.map(\.1).joined()
  }
}

public struct ShortcutChord: Codable, Hashable, Sendable {
  public let keyCode: Int
  public let modifiers: ShortcutModifiers
  public init(_ keyCode: Int, modifiers: ShortcutModifiers = [.control, .option]) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }
  public var engineValue: String {
    let prefix = modifiers.isEmpty ? "" : modifiers.engineValue + " - "
    return prefix + "keycode:\(keyCode)"
  }
  public var validationMessage: String? {
    guard (0...126).contains(keyCode), ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode),
      modifiers.rawValue & ~ShortcutModifiers.all.rawValue == 0
    else { return "Choose a regular key with modifier keys." }
    if modifiers.contains(.function) && modifiers != .function {
      return "Fn cannot be combined with other modifiers. Choose a different combination."
    }
    guard
      !modifiers.intersection([.control, .option, .command, .function]).isEmpty
        || Self.functionKeys.contains(keyCode)
    else { return "Include Control, Option or Command, or use a function key." }
    let reserved: [(ShortcutModifiers, [Int])] = [
      ([.command], [12, 13, 4, 43, 48, 49]),
      ([.command, .shift], [20, 21, 23]),
      ([.control, .command], [12, 49]),
      ([.command, .option], [49, 53]),
      ([.control], [123, 124, 125, 126]),
    ]
    if reserved.contains(where: { $0.0 == modifiers && $0.1.contains(keyCode) }) {
      return "This shortcut is reserved by macOS. Choose a different combination."
    }
    return nil
  }
  public static let functionKeys: Set<Int> = [
    64, 79, 80, 90, 96, 97, 98, 99, 100, 101, 103, 105, 106, 107, 109, 111, 113, 118, 120, 122,
  ]
}

/// Every global action offered by Ribbon. Engine-only workspace and scripting commands stay private.
public enum ShortcutAction: String, CaseIterable, Identifiable, Sendable {
  case overview = "window_overview"
  case focusLeft = "window_focus_west"
  case focusRight = "window_focus_east"
  case focusUp = "window_focus_north"
  case focusDown = "window_focus_south"
  case focusFirst = "window_focus_first"
  case focusLast = "window_focus_last"
  case moveLeft = "window_swap_west"
  case moveRight = "window_swap_east"
  case moveUp = "window_swap_north"
  case moveDown = "window_swap_south"
  case pairLeft = "window_pair_west"
  case pairRight = "window_pair_east"
  case unpair = "window_unpair"
  case pairHalf = "window_pairfit_half"
  case pairThird = "window_pairfit_third"
  case pairTwoThirds = "window_pairfit_twothirds"
  case width = "window_resize"
  case narrower = "window_resize_shrink"
  case taller = "window_vertical_resize_grow"
  case shorter = "window_vertical_resize_shrink"
  case fullWidth = "window_fullwidth"
  case center = "window_center"
  case fit = "window_snap"
  case balance = "window_balance"
  case equalize = "window_equalize"
  case stack = "window_stack"
  case unstack = "window_unstack"
  case tabs = "window_tabbeddisplay"
  case float = "window_manage"
  case nextDisplay = "window_nextdisplay"
  case sendDisplay = "window_nextdisplaysend"
  case pause = "quit"
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .overview: "Arrange windows"
    case .focusLeft: "Focus left"
    case .focusRight: "Focus right"
    case .focusUp: "Focus above"
    case .focusDown: "Focus below"
    case .focusFirst: "Focus first column"
    case .focusLast: "Focus last column"
    case .moveLeft: "Move left"
    case .moveRight: "Move right"
    case .moveUp: "Move up in stack"
    case .moveDown: "Move down in stack"
    case .pairLeft: "Pair with left"
    case .pairRight: "Pair with right"
    case .unpair: "Ungroup pair"
    case .pairHalf: "Arrange ½–½"
    case .pairThird: "Arrange ⅓–⅔"
    case .pairTwoThirds: "Arrange ⅔–⅓"
    case .width: "Cycle wider widths"
    case .narrower: "Cycle narrower widths"
    case .taller: "Increase stack height"
    case .shorter: "Decrease stack height"
    case .fullWidth: "Toggle full width"
    case .center: "Center column"
    case .fit: "Fit in display"
    case .balance: "Match column widths"
    case .equalize: "Equalize stack heights"
    case .stack: "Stack window"
    case .unstack: "Unstack window"
    case .tabs: "Toggle stack tabs"
    case .float: "Toggle floating window"
    case .nextDisplay: "Move to next display"
    case .sendDisplay: "Send to next display"
    case .pause: "Pause and restore windows"
    }
  }
  public var group: String {
    switch self {
    case .overview: "Arrange"
    case .focusLeft, .focusRight, .focusUp, .focusDown, .focusFirst, .focusLast: "Focus"
    case .moveLeft, .moveRight, .moveUp, .moveDown, .pairLeft, .pairRight, .unpair: "Arrange"
    case .pairHalf, .pairThird, .pairTwoThirds, .width, .narrower, .taller, .shorter, .fullWidth,
      .center, .fit, .balance, .equalize:
      "Size & position"
    case .stack, .unstack, .tabs, .float: "Stacks & floating"
    case .nextDisplay, .sendDisplay: "Displays"
    case .pause: "Session"
    }
  }
  public var detail: String? {
    switch self {
    case .nextDisplay: "Move the window and follow it."
    case .sendDisplay: "Move the window and keep focus here."
    case .balance: "Use the focused column’s width for every column."
    case .equalize: "Give each window in the stack the same height."
    case .pause: "Stop arranging windows and restore their original frames."
    default: nil
    }
  }
  public var defaults: [ShortcutChord] {
    switch self {
    case .overview: [ShortcutChord(48)]
    case .focusLeft: [ShortcutChord(123)]
    case .focusRight: [ShortcutChord(124)]
    case .focusUp: [ShortcutChord(126)]
    case .focusDown: [ShortcutChord(125)]
    case .moveLeft: [ShortcutChord(123, modifiers: [.control, .option, .shift])]
    case .moveRight: [ShortcutChord(124, modifiers: [.control, .option, .shift])]
    case .width: [ShortcutChord(15)]
    case .fullWidth: [ShortcutChord(3)]
    case .center: [ShortcutChord(8)]
    case .stack: [ShortcutChord(30)]
    case .unstack: [ShortcutChord(30, modifiers: [.control, .option, .shift])]
    case .tabs: [ShortcutChord(17, modifiers: [.control, .option, .shift])]
    case .float: [ShortcutChord(17)]
    case .nextDisplay: [ShortcutChord(45)]
    case .pause: [ShortcutChord(12)]
    default: []
    }
  }
  public static let groups = [
    "Focus", "Arrange", "Size & position", "Stacks & floating", "Displays", "Session",
  ]
}

extension RibbonSettings {
  public func shortcuts(for action: ShortcutAction) -> [ShortcutChord] {
    shortcutOverrides[action.rawValue] ?? action.defaults
  }
  public mutating func setShortcuts(_ chords: [ShortcutChord], for action: ShortcutAction) throws {
    var candidate = self
    candidate.shortcutOverrides[action.rawValue] = chords
    try candidate.validateShortcuts()
    self = candidate
  }
  public func validateShortcuts() throws {
    guard shortcutOverrides.keys.allSatisfy({ ShortcutAction(rawValue: $0) != nil }) else {
      throw ShortcutError.invalid("An unknown shortcut action was saved.")
    }
    var assigned: [ShortcutChord: ShortcutAction] = [:]
    for action in ShortcutAction.allCases {
      let chords = shortcuts(for: action)
      guard chords.count <= 3 else {
        throw ShortcutError.invalid("Use up to three shortcuts per action.")
      }
      for chord in chords {
        if let message = chord.validationMessage { throw ShortcutError.invalid(message) }
        if let other = assigned[chord] {
          throw ShortcutError.invalid("Already assigned to \(other.title.lowercased()).")
        }
        assigned[chord] = action
      }
    }
  }
  public var bindingsConfiguration: String {
    ShortcutAction.allCases.map { action in
      let values = shortcuts(for: action).map { "\"\($0.engineValue)\"" }.joined(separator: ", ")
      return "\(action.rawValue) = [\(values)]"
    }.joined(separator: "\n")
  }
}

public enum ShortcutError: Error, LocalizedError {
  case invalid(String)
  public var errorDescription: String? {
    switch self {
    case .invalid(let message): message
    }
  }
}
