import Foundation

public struct CommandResult: Sendable {
  public let status: Int32
  public let output: String
  public let errorOutput: String
}

public enum CommandError: Error, LocalizedError {
  case timedOut
  public var errorDescription: String? { "The window engine did not respond in time." }
}

public struct CommandRunner: Sendable {
  public init() {}

  public func run(
    _ executable: URL, arguments: [String], environment: [String: String] = [:],
    timeout: TimeInterval = 3
  ) async throws -> CommandResult {
    try await Task.detached(priority: .utility) {
      try Self.execute(executable, arguments: arguments, environment: environment, timeout: timeout)
    }.value
  }

  private static func execute(
    _ executable: URL, arguments: [String], environment: [String: String],
    timeout: TimeInterval
  ) throws -> CommandResult {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ribbon-command-\(UUID())")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("stdout")
    let errors = directory.appendingPathComponent("stderr")
    for url in [output, errors] {
      guard
        FileManager.default.createFile(
          atPath: url.path, contents: nil,
          attributes: [.posixPermissions: 0o600])
      else { throw CocoaError(.fileWriteUnknown) }
    }
    let outHandle = try FileHandle(forWritingTo: output)
    let errHandle = try FileHandle(forWritingTo: errors)
    defer {
      try? outHandle.close()
      try? errHandle.close()
    }
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    process.standardOutput = outHandle
    process.standardError = errHandle
    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }
    try process.run()
    if exited.wait(timeout: .now() + timeout) == .timedOut {
      if process.isRunning { process.terminate() }
      if exited.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning {
        kill(process.processIdentifier, SIGKILL)
        _ = exited.wait(timeout: .now() + 0.5)
      }
      throw CommandError.timedOut
    }
    // Files avoid pipe back-pressure and inherited pipe descriptors on timeout.
    func readBounded(_ url: URL) throws -> String {
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      let data = try handle.read(upToCount: 1_048_576) ?? Data()
      return String(decoding: data, as: UTF8.self)
    }
    return try CommandResult(
      status: process.terminationStatus, output: readBounded(output),
      errorOutput: readBounded(errors))
  }
}
