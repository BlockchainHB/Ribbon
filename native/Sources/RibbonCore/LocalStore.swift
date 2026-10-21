import Foundation

public struct LocalStore: Sendable {
  public let directory: URL

  public init(directory: URL) { self.directory = directory }

  public static var standard: Self {
    Self(
      directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Ribbon", isDirectory: true))
  }

  public func prepare() throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
  }

  public func write<T: Encodable>(_ value: T, to name: String) throws {
    try prepare()
    let data = try JSONEncoder().encode(value)
    let url = directory.appendingPathComponent(name)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  public func read<T: Decodable>(_ type: T.Type, from name: String) throws -> T? {
    let url = directory.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode(type, from: Data(contentsOf: url))
  }

  public func remove(_ name: String) throws {
    let url = directory.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }
}
