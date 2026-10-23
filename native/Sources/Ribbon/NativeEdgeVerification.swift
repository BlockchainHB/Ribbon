import AppKit
import ApplicationServices
import Darwin

/// Permission-context experiment only. Never starts an engine or touches an existing window.
@MainActor
enum NativeEdgeVerification {
  private static let controllerFlag = "--qa-native-edge"
  private static let childFlag = "--qa-native-edge-child"

  private struct Failure: Error { let message: String }
  private struct Frame: Codable {
    let x: Double, y: Double, width: Double, height: Double
    init(_ rect: CGRect) {
      x = rect.minX
      y = rect.minY
      width = rect.width
      height = rect.height
    }
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    func matches(_ other: Frame) -> Bool {
      zip([x, y, width, height], [other.x, other.y, other.width, other.height])
        .allSatisfy { abs($0 - $1) <= 1 }
    }
  }
  private struct Request: Codable {
    let sequence: Int
    let frame: Frame
  }
  private struct ChildState: Codable {
    let pid: Int32
    let id: UInt32
    let connection: Int32
    let sequence: Int
    let client: Frame
    let local: Frame
    let server: Frame
    let contentWidth: Double
  }
  private struct Observation: Codable {
    let callerLocal: Frame
    let callerServer: Frame
    let child: ChildState
  }
  private struct Receipt: Codable {
    let display: String
    let direction: String
    let shapeStatus: Int32
    let moveStatus: Int32
    let expectedBody: Frame
    let expectedContent: Frame
    let before: Observation
    let observations: [Observation]
    let independentlyConfirmed: Bool
  }
  private struct OwnedControl: Codable {
    let shapeStatus: Int32
    let moveStatus: Int32
    let expectedBody: Frame
    let observedServer: Frame
    let confirmed: Bool
  }
  private struct Report: Encodable {
    var status = "running"
    var detail: String?
    let accessibilityTrusted = AXIsProcessTrusted()
    let screenCaptureAllowed = CGPreflightScreenCaptureAccess()
    let system = ProcessInfo.processInfo.operatingSystemVersionString
    var displays: [Frame] = []
    var ownedControl: OwnedControl?
    var receipts: [Receipt] = []
  }

  private typealias Connection = @convention(c) () -> Int32
  private typealias Bounds = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGRect>) -> Int32
  private typealias Owner = @convention(c) (Int32, UInt32, UnsafeMutablePointer<Int32>) -> Int32
  private typealias NewRegion =
    @convention(c) (
      UnsafePointer<CGRect>, UnsafeMutablePointer<UnsafeRawPointer?>
    ) -> Int32
  private typealias Shape = @convention(c) (Int32, UInt32, Float, Float, UnsafeRawPointer) -> Int32
  private typealias Move = @convention(c) (Int32, UInt32, UnsafePointer<CGPoint>) -> Int32

  private struct NativeAPI {
    let library: UnsafeMutableRawPointer
    let connection: Int32
    let bounds: Bounds
    let owner: Owner

    init() throws {
      guard
        let library = dlopen(
          "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
        let main = dlsym(library, "SLSMainConnectionID"),
        let bounds = dlsym(library, "SLSGetWindowBounds"),
        let owner = dlsym(library, "SLSGetWindowOwner")
      else { throw Failure(message: "Native query capability unavailable") }
      self.library = library
      connection = unsafeBitCast(main, to: Connection.self)()
      self.bounds = unsafeBitCast(bounds, to: Bounds.self)
      self.owner = unsafeBitCast(owner, to: Owner.self)
    }

    func localFrame(_ id: UInt32) throws -> Frame {
      var frame = CGRect.zero
      guard bounds(connection, id, &frame) == 0 else {
        throw Failure(message: "Native bounds query failed")
      }
      return Frame(frame)
    }

    func serverFrame(_ id: UInt32) throws -> Frame {
      guard
        let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id)
          as? [[String: Any]],
        let window = windows.first,
        let dictionary = window[kCGWindowBounds as String] as? [String: Any],
        let frame = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
      else {
        throw Failure(message: "Independent WindowServer bounds unavailable for fixture \(id)")
      }
      return Frame(frame)
    }

    func crop(_ id: UInt32, source: CGRect, destination: CGPoint) throws -> (Int32, Int32) {
      guard let make = dlsym(library, "CGSNewRegionWithRect"),
        let shape = dlsym(library, "SLSSetWindowShape"),
        let move = dlsym(library, "SLSMoveWindow")
      else { throw Failure(message: "Native shape/move capability unavailable") }
      var source = source
      var raw: UnsafeRawPointer?
      guard unsafeBitCast(make, to: NewRegion.self)(&source, &raw) == 0, let raw else {
        throw Failure(message: "Native region creation failed")
      }
      let retained = Unmanaged<AnyObject>.fromOpaque(raw).takeRetainedValue()
      var destination = destination
      return withExtendedLifetime(retained) {
        (
          unsafeBitCast(shape, to: Shape.self)(connection, id, 0, 0, raw),
          unsafeBitCast(move, to: Move.self)(connection, id, &destination)
        )
      }
    }
  }

  static func startIfRequested() -> Bool {
    let arguments = CommandLine.arguments
    guard arguments.contains(controllerFlag) || arguments.contains(childFlag) else { return false }
    guard arguments.count == 3, [controllerFlag, childFlag].contains(arguments[1]) else {
      fputs("Expected --qa-native-edge FRESH_OUTPUT\n", stderr)
      exit(2)
    }
    let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
    let child = arguments[1] == childFlag
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    Task { @MainActor in
      do {
        if child { try await serve(output) } else { try await verify(output) }
        app.terminate(nil)
      } catch {
        fputs("Native edge diagnostic stopped: \(error)\n", stderr)
        exit(1)
      }
    }
    app.run()
    return true
  }

  private static func write<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url, options: .atomic)
  }

  private static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: url))
  }

  private static func serve(_ output: URL) async throws {
    let api = try NativeAPI()
    let window = NSWindow(
      contentRect: CGRect(x: 100, y: 300, width: 800, height: 400),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.title = "Ribbon invisible edge diagnostic"
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    window.orderBack(nil)
    defer { window.close() }
    try await Task.sleep(for: .milliseconds(100))
    let parent = getppid()
    let deadline = Date().addingTimeInterval(30)
    let response = output.appendingPathComponent("child.json")
    var sequence = 0
    while Date() < deadline, getppid() == parent, kill(parent, 0) == 0 {
      if let request = try? read(Request.self, from: output.appendingPathComponent("request.json")),
        request.sequence != sequence
      {
        // Force the owning app to restore its real geometry even if its cached frame matches.
        window.setFrameOrigin(CGPoint(x: request.frame.x + 1, y: request.frame.y))
        window.setFrame(request.frame.rect, display: true)
        sequence = request.sequence
      }
      let id = UInt32(window.windowNumber)
      try write(
        ChildState(
          pid: getpid(), id: id, connection: api.connection, sequence: sequence,
          client: Frame(window.frame), local: try api.localFrame(id),
          server: try api.serverFrame(id),
          contentWidth: Double(window.contentView?.bounds.width ?? 0)),
        to: response)
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  private static func verifyOwnedControl(_ api: NativeAPI) async throws -> OwnedControl {
    let window = NSWindow(
      contentRect: CGRect(x: 100, y: 300, width: 800, height: 400),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    window.orderBack(nil)
    defer { window.close() }
    try await Task.sleep(for: .milliseconds(100))
    let id = UInt32(window.windowNumber)
    let before = try api.serverFrame(id).rect
    let expected = CGRect(x: before.minX, y: before.minY, width: 200, height: before.height)
    let (shape, move) = try api.crop(
      id, source: CGRect(origin: .zero, size: expected.size), destination: expected.origin)
    try await Task.sleep(for: .milliseconds(100))
    let observed = try api.serverFrame(id)
    return OwnedControl(
      shapeStatus: shape, moveStatus: move, expectedBody: Frame(expected),
      observedServer: observed,
      confirmed: shape == 0 && move == 0 && Frame(expected).matches(observed))
  }

  private static func verify(_ output: URL) async throws {
    try FileManager.default.createDirectory(
      at: output, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    var report = Report()
    let reportURL = output.appendingPathComponent("report.json")
    do {
      guard report.accessibilityTrusted else {
        throw Failure(message: "Signed Ribbon has no Accessibility grant in this launch context")
      }
      let check = Process()
      check.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
      check.arguments = ["-x", "ribbon-engine"]
      check.standardOutput = FileHandle.nullDevice
      try check.run()
      check.waitUntilExit()
      let screens = NSScreen.screens
      let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
      guard check.terminationStatus == 1, screens.count == 2,
        NSScreen.screensHaveSeparateSpaces,
        session["CGSSessionScreenIsLocked"] as? Bool != true
      else { throw Failure(message: "Requires paused Ribbon and an unlocked two-display desktop") }
      report.displays = screens.map { Frame($0.frame) }
      let api = try NativeAPI()
      report.ownedControl = try await verifyOwnedControl(api)
      try write(report, to: reportURL)
      guard let executable = Bundle.main.executableURL else {
        throw Failure(message: "Signed Ribbon executable unavailable")
      }
      let child = Process()
      child.executableURL = executable
      child.arguments = [childFlag, output.path]
      try child.run()
      defer {
        if child.isRunning { child.terminate() }
        child.waitUntilExit()
      }
      let response = output.appendingPathComponent("child.json")
      for _ in 0..<100 where !FileManager.default.fileExists(atPath: response.path) {
        try await Task.sleep(for: .milliseconds(20))
      }
      let identity = try read(ChildState.self, from: response)
      var owner: Int32 = 0
      guard identity.pid == child.processIdentifier, identity.connection != api.connection,
        api.owner(api.connection, identity.id, &owner) == 0, owner == identity.connection
      else { throw Failure(message: "Refusing to operate outside the owned child window") }
      var sequence = 0
      for screen in screens {
        let frame = screen.visibleFrame.insetBy(dx: 6, dy: 0)
        let nativeY = (screens.first?.frame.maxY ?? 0) - frame.maxY
        for direction in ["left", "right"] {
          sequence += 1
          try write(
            Request(sequence: sequence, frame: Frame(frame)),
            to: output.appendingPathComponent("request.json"))
          var ready = false
          for _ in 0..<100 {
            if try read(ChildState.self, from: response).sequence == sequence {
              ready = true
              break
            }
            try await Task.sleep(for: .milliseconds(10))
          }
          guard ready else { throw Failure(message: "Owned fixture did not acknowledge geometry") }
          let destination = CGPoint(
            x: direction == "left" ? frame.minX : frame.maxX - 200, y: nativeY)
          let source = CGRect(
            x: direction == "left" ? frame.width - 200 : 0, y: 0,
            width: 200, height: frame.height)
          let expected = Frame(CGRect(origin: destination, size: source.size))
          let before = Observation(
            callerLocal: try api.localFrame(identity.id),
            callerServer: try api.serverFrame(identity.id),
            child: try read(ChildState.self, from: response))
          let (shape, move) = try api.crop(identity.id, source: source, destination: destination)
          var observations: [Observation] = []
          for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(100))
            observations.append(
              Observation(
                callerLocal: try api.localFrame(identity.id),
                callerServer: try api.serverFrame(identity.id),
                child: try read(ChildState.self, from: response)))
          }
          let confirmed =
            shape == 0 && move == 0
            && observations.allSatisfy {
              expected.matches($0.callerServer) && expected.matches($0.child.server)
                && expected.matches($0.child.local) && $0.child.contentWidth == frame.width
                && $0.child.client.height == frame.height
            }
          report.receipts.append(
            Receipt(
              display: screen.localizedName, direction: direction,
              shapeStatus: shape, moveStatus: move, expectedBody: expected,
              expectedContent: Frame(frame), before: before, observations: observations,
              independentlyConfirmed: confirmed))
          try write(report, to: reportURL)
        }
      }
      report.status =
        report.receipts.allSatisfy(\.independentlyConfirmed) ? "confirmed" : "rejected"
      report.detail =
        "Geometry experiment only; no compositor pacing or application-interaction proof"
    } catch {
      report.status = "blocked"
      report.detail = String(describing: error)
    }
    try write(report, to: reportURL)
  }
}
