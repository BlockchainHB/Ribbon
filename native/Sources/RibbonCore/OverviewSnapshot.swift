import Foundation

/// Read-only engine response. The app never predicts or persists tile order.
public struct OverviewSnapshot: Decodable, Sendable {
  public let displays: [Display]
  public let focused: Int32?
  public struct Display: Decodable, Identifiable, Sendable {
    public let id: UInt32
    public let active: Bool
    public let workspaces: [Workspace]
    public var columns: [Column] { workspaces.filter(\.active).flatMap(\.columns) }
  }
  public struct Workspace: Decodable, Sendable {
    public let active: Bool
    public let columns: [Column]
  }
  public struct Column: Decodable, Identifiable, Sendable {
    public let pairID: UInt64?
    enum CodingKeys: String, CodingKey {
      case kind, selected, windows
      case pairID = "pair_id"
    }
    public let kind: String
    public let selected: Int
    public let windows: [Window]
    public var representative: Window? {
      windows.indices.contains(selected) ? windows[selected] : windows.first
    }
    public var id: Int32 { representative?.id ?? 0 }
    public func contains(_ id: Int32) -> Bool { windows.contains { $0.id == id } }
  }
  public struct Window: Decodable, Identifiable, Sendable {
    public let id: Int32
    public let appName: String
    public let bundleID: String
    public let title: String
    enum CodingKeys: String, CodingKey {
      case id, title
      case appName = "app_name"
      case bundleID = "bundle_id"
    }
  }
  public func movementRange(containing id: Int32) -> Range<Int>? {
    guard let columns = columns(containing: id),
      let index = columns.firstIndex(where: { $0.contains(id) })
    else { return nil }
    guard let pair = columns[index].pairID else { return index..<index + 1 }
    let members = columns.indices.filter { columns[$0].pairID == pair }
    guard let first = members.first, let last = members.last else { return nil }
    return first..<last + 1
  }
  public func columns(containing id: Int32) -> [Column]? {
    displays.first { $0.columns.contains { $0.contains(id) } }?.columns
  }
}
