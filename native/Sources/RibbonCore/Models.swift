import CoreGraphics
import Foundation

public enum EngineCommand: String, CaseIterable, Sendable {
  case first, left, right, up, down, width, fullWidth, center, stack, unstack, tabs, float,
    nextDisplay, sendDisplay, fit

  public var arguments: [String] {
    let operation: [String]
    switch self {
    case .first: operation = ["focus", "first"]
    case .left: operation = ["focus", "west"]
    case .right: operation = ["focus", "east"]
    case .up: operation = ["focus", "north"]
    case .down: operation = ["focus", "south"]
    case .width: operation = ["resize"]
    case .fullWidth: operation = ["fullwidth"]
    case .center: operation = ["center"]
    case .stack: operation = ["stack"]
    case .unstack: operation = ["unstack"]
    case .tabs: operation = ["tabbeddisplay"]
    case .float: operation = ["manage"]
    case .nextDisplay: operation = ["nextdisplay"]
    case .sendDisplay: operation = ["nextdisplaysend"]
    case .fit: operation = ["snap"]
    }
    return ["send-cmd", "window"] + operation
  }
}

public struct EngineState: Decodable, Sendable {
  public let version: Int
  public let active: Active
  public let virtualWorkspaces: [Workspace]
  public var windows: [Window] { virtualWorkspaces.flatMap(\.windows) }
  enum CodingKeys: String, CodingKey {
    case version, active
    case virtualWorkspaces = "virtual_workspaces"
  }
  public struct Active: Decodable, Sendable {
    public let focusedWindowID: Int32?
    enum CodingKeys: String, CodingKey { case focusedWindowID = "focused_window_id" }
  }
  public struct Workspace: Decodable, Sendable { public let windows: [Window] }
  public struct Window: Decodable, Sendable {
    public let windowID: Int32
    public let bundleID: String
    public let floating: Bool
    public let visible: Bool?
    public let displayID: UInt32?
    /// Read-only logical bounds supplied by the engine, before native edge fitting.
    public let frame: WindowFrame?
    enum CodingKeys: String, CodingKey {
      case windowID = "window_id"
      case bundleID = "bundle_id"
      case floating, visible, frame
      case displayID = "display_id"
    }
  }
}

public struct WindowFrame: Codable, Equatable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(_ rect: CGRect) {
    x = rect.minX
    y = rect.minY
    width = rect.width
    height = rect.height
  }

  public var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
  public var isValid: Bool {
    [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
  }
}

public struct SavedWindow: Codable, Equatable, Sendable {
  public let pid: Int32
  public let bundleID: String
  public let launchTime: Double
  public let windowID: UInt32
  public let frame: WindowFrame

  public init(
    pid: Int32, bundleID: String, launchTime: Double, windowID: UInt32, frame: WindowFrame
  ) {
    self.pid = pid
    self.bundleID = bundleID
    self.launchTime = launchTime
    self.windowID = windowID
    self.frame = frame
  }

  public func belongs(toPID currentPID: Int32, bundle: String, launchedAt: Double) -> Bool {
    pid == currentPID && bundleID == bundle && abs(launchTime - launchedAt) < 0.001
  }
}

public struct RecoveryJournal: Codable, Equatable, Sendable {
  public let version: Int
  public let sessionID: UUID
  public let windows: [SavedWindow]
  public let managedBundleIDs: Set<String>
  public let scope: ManagementScope
  public let excludedBundleIDs: Set<String>

  public init(
    windows: [SavedWindow], managedBundleIDs: Set<String>? = nil,
    scope: ManagementScope = .selected, excludedBundleIDs: Set<String> = []
  ) {
    version = scope == .all ? 2 : 1
    sessionID = UUID()
    self.windows = windows
    self.managedBundleIDs = managedBundleIDs ?? Set(windows.map(\.bundleID))
    self.scope = scope
    self.excludedBundleIDs = excludedBundleIDs
  }

  private enum CodingKeys: String, CodingKey {
    case version, sessionID, windows, managedBundleIDs, scope, excludedBundleIDs
  }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version)
    sessionID = try values.decode(UUID.self, forKey: .sessionID)
    windows = try values.decode([SavedWindow].self, forKey: .windows)
    managedBundleIDs = try values.decode(Set<String>.self, forKey: .managedBundleIDs)
    scope = try values.decodeIfPresent(ManagementScope.self, forKey: .scope) ?? .selected
    excludedBundleIDs =
      try values.decodeIfPresent(Set<String>.self, forKey: .excludedBundleIDs) ?? []
  }

  public func recoveryBundleIDs(in running: Set<String>) -> Set<String> {
    if scope != .all { return managedBundleIDs }
    return running.filter {
      RibbonSettings.validBundleID($0) && !RibbonSettings.protectedBundleIDs.contains($0)
        && !excludedBundleIDs.contains($0)
    }
  }

  public func validated() throws -> Self {
    guard (version == 1 && scope != .all) || version == 2,
      windows.count <= 1000,
      managedBundleIDs.allSatisfy(RibbonSettings.validBundleID),
      excludedBundleIDs.allSatisfy(RibbonSettings.validBundleID),
      managedBundleIDs.isDisjoint(with: RibbonSettings.protectedBundleIDs),
      scope != .all || managedBundleIDs.isDisjoint(with: excludedBundleIDs),
      windows.allSatisfy({
        $0.pid > 1 && $0.windowID > 0 && $0.frame.isValid
          && RibbonSettings.validBundleID($0.bundleID) && $0.launchTime.isFinite
          && managedBundleIDs.contains($0.bundleID)
      })
    else { throw SettingsError.invalid }
    return self
  }
}
