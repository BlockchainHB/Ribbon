import AppKit
import ApplicationServices
import CryptoKit
import RibbonCore

struct FixtureFrame: Codable {
  let id: UInt32
  let x: Double, y: Double, width: Double, height: Double
  let focused: Bool
  let screenID: UInt32
  let minimumWidth: Double?
  func matches(_ other: Self) -> Bool {
    abs(x - other.x) < 4 && abs(y - other.y) < 4 && abs(width - other.width) < 4
      && abs(height - other.height) < 4
  }
}

@MainActor
enum DesktopVerification {
  private static var started = false
  struct Check: Encodable {
    let name: String
    let passed: Bool
  }
  struct Report: Encodable {
    var status = "running"
    var system = ProcessInfo.processInfo.operatingSystemVersionString
    var checks: [Check] = []
    var motion: [MotionObservation] = []
    var commandToObservedFocusMS: [Double] = []
    var frames: [String: [FixtureFrame]] = [:]
    var detail: String?
    var engineSHA256: String?
    var displays: [DisplaySnapshot] = []
    var animationClock =
      CommandLine.arguments.contains("--qa-display-clock") ? "display-link" : "legacy"
  }
  struct DisplaySnapshot: Encodable {
    let name: String
    let id: UInt32
    let x: Double, y: Double, width: Double, height: Double, scale: Double
    init(_ screen: NSScreen) {
      name = screen.localizedName
      id =
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
        .uint32Value ?? 0
      x = screen.frame.minX
      y = (NSScreen.screens.first?.frame.maxY ?? 0) - screen.frame.maxY
      width = screen.frame.width
      height = screen.frame.height
      scale = screen.backingScaleFactor
    }
  }

  static func run(_ controller: SessionController, statusMenu: RibbonStatusMenu?) async {
    guard !started, let index = CommandLine.arguments.firstIndex(of: "--qa-output"),
      CommandLine.arguments.indices.contains(index + 1)
    else { return }
    started = true
    let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    let fixture = output.deletingLastPathComponent().appendingPathComponent("fixture-frames.json")
    let sentinel = output.deletingLastPathComponent().appendingPathComponent("sentinel-frames.json")
    var report = Report()
    report.displays = NSScreen.screens.map(DisplaySnapshot.init)
    var owned: [NSRunningApplication] = []
    do {
      let fixedContent = CommandLine.arguments.contains("--qa-fixed-content")
      if fixedContent {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        try require(
          session["CGSSessionScreenIsLocked"] as? Bool != true, "Desktop must be unlocked")
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        check.arguments = ["-x", "ribbon-engine"]
        check.standardOutput = FileHandle.nullDevice
        try check.run()
        check.waitUntilExit()
        try require(check.terminationStatus != 0, "Pause Ribbon before isolated fixture QA")
      }
      try FileManager.default.createDirectory(
        at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
      report.engineSHA256 = SHA256.hash(data: try Data(contentsOf: controller.engineURL)).map {
        String(format: "%02x", $0)
      }.joined()
      await controller.refreshPermission()
      guard controller.permissionGranted, AXIsProcessTrusted() else {
        report.status = "blocked"
        report.detail =
          "Accessibility access is required for the signed local Ribbon app. No window manager was started."
        try write(report, to: output)
        return
      }
      try await eventually("Sidebar settings window appeared") {
        NSApp.windows.contains { window in
          window.canBecomeMain && window.contentLayoutRect.width >= 740
        }
      }
      report.checks.append(Check(name: "native sidebar settings window", passed: true))
      for app in NSWorkspace.shared.runningApplications
      where [RibbonSettings.fixtureBundleID, "dev.ribbon.sentinel"].contains(
        app.bundleIdentifier ?? "")
      {
        throw VerificationError.failed(
          "An existing demo test app is open. Close it before this isolated test run.")
      }
      if !fixedContent { try await verifyStatusItem(statusMenu, report: &report) }
      let dualDisplays = CommandLine.arguments.contains("--qa-dual")
      if dualDisplays && NSScreen.screens.count != 2 {
        throw VerificationError.failed("Dual-display QA requires exactly two connected displays")
      }
      let expectedWindows = dualDisplays ? 8 : 4
      controller.settings = RibbonSettings()
      controller.settings.scope = .demo
      try await controller.openDemo(report: fixture, dualDisplays: dualDisplays)
      owned += NSRunningApplication.runningApplications(
        withBundleIdentifier: RibbonSettings.fixtureBundleID)
      let config = NSWorkspace.OpenConfiguration()
      config.arguments = ["--report", sentinel.path]
      let sentinelApp = try await NSWorkspace.shared.openApplication(
        at: Bundle.main.resourceURL!.appendingPathComponent("Ribbon Sentinel.app"),
        configuration: config)
      owned.append(sentinelApp)
      try await eventually("Fixture windows opened") {
        try frames(fixture).count == expectedWindows && frames(sentinel).count == 1
      }
      let original = try await settledFrames(fixture)
      let excluded = try await settledFrames(sentinel)
      report.frames["original"] = original
      report.frames["excluded"] = excluded
      try await clickSessionSwitch(controller, running: true)
      try require(controller.phase == .running, "Engine became ready")
      try await eventually("Only fixture windows are managed") {
        let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
        return state.version == 1 && state.windows.count == expectedWindows
          && state.windows.allSatisfy { $0.bundleID == RibbonSettings.fixtureBundleID }
      }
      report.checks.append(Check(name: "start and exact application scope", passed: true))
      if fixedContent {
        if CommandLine.arguments.contains("--qa-oversized") {
          try await verifyOversizedFocus(controller, fixture: fixture, report: &report)
        } else {
          try await verifyFixedContent(controller, fixture: fixture, report: &report)
        }
        if CommandLine.arguments.contains("--qa-pairing")
          && !CommandLine.arguments.contains("--qa-oversized")
        {
          try await verifyPairing(controller, fixture: fixture, report: &report)
        }
      } else if CommandLine.arguments.contains("--qa-maximized-startup") {
        try await verifyMaximizedStartup(
          controller, fixture: fixture, original: original, report: &report)
      } else if CommandLine.arguments.contains("--qa-pairing") {
        try await verifyPairing(controller, fixture: fixture, report: &report)
      } else if CommandLine.arguments.contains("--qa-motion") {
        try await verifyMotion(controller, fixture: fixture, report: &report)
        try await verifyOverview(controller, fixture: fixture, report: &report)
      } else if CommandLine.arguments.contains("--qa-overview") {
        try await verifyOverview(controller, fixture: fixture, report: &report)
      } else if CommandLine.arguments.contains("--qa-width-policy") {
        try await verifyWidthPolicy(controller, fixture: fixture, report: &report)
      } else if dualDisplays {
        try await verifyDual(controller, fixture: fixture, original: original, report: &report)
        if CommandLine.arguments.contains("--qa-raycast") {
          try await verifyRaycastOpening(
            controller, fixture: fixture, original: original, owned: &owned, report: &report)
        }
      } else {
        try await verifyApplicationOpening(
          controller, fixture: fixture, owned: &owned, report: &report)
        try await verifyMotion(controller, fixture: fixture, report: &report)
        await controller.send(.first)
        try await eventually("First fixture receives focus") {
          try frames(fixture).contains(where: \.focused)
        }
        _ = try await settledFrames(fixture)
        let tiledState = try JSONDecoder().decode(EngineState.self, from: await controller.query())
        for direction: EngineCommand in [
          .right, .right, .left, .left, .right, .right, .left, .left,
        ] {
          let before = try frames(fixture).first(where: \.focused)?.id
          let start = ProcessInfo.processInfo.systemUptime
          await controller.send(direction)
          try require(
            try await changedFocus(fixture, from: before, timeout: 3),
            "Navigation changes native focus")
          report.commandToObservedFocusMS.append(
            (ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        report.checks.append(
          Check(name: "repeated navigation reaches actual native windows", passed: true))
        let navigated = try await settledFrames(fixture)
        let navigatedState = try JSONDecoder().decode(
          EngineState.self, from: await controller.query())
        try requirePreservedWidths(
          from: tiledState, to: navigatedState,
          message: "Navigation preserved logical widths")
        report.checks.append(Check(name: "navigation preserves widths", passed: true))
        await controller.send(.width)
        try await eventually("Width preset changes a native frame") {
          try frames(fixture).contains { new in
            navigated.contains { $0.id == new.id && abs($0.width - new.width) > 10 }
          }
        }
        report.checks.append(Check(name: "width presets change actual frames", passed: true))
        let beforeNew = try await settledFrames(fixture)
        let beforeNewState = try JSONDecoder().decode(
          EngineState.self, from: await controller.query())
        report.frames["beforeNewWindow"] = beforeNew
        DistributedNotificationCenter.default().postNotificationName(
          NSNotification.Name("dev.ribbon.fixture.add-window"), object: nil, userInfo: nil,
          deliverImmediately: true)
        try await eventually("New fixture enters strip") {
          let state = try JSONDecoder().decode(EngineState.self, from: await controller.query())
          let frameCount = try frames(fixture).count
          return state.windows.count == 5 && frameCount == 5
        }
        let afterNew = try await settledFrames(fixture)
        report.frames["afterNewWindow"] = afterNew
        let afterNewState = try JSONDecoder().decode(
          EngineState.self, from: await controller.query())
        // A new slot can clip an existing native body at the display edge.
        // Preferred sizing remains in the engine's logical bounds.
        try requirePreservedWidths(
          from: beforeNewState, to: afterNewState,
          message: "Opening another window preserved logical widths")
        report.checks.append(Check(name: "opening windows preserves existing widths", passed: true))
        await controller.send(.stack)
        try await eventually("Stack shares a column") {
          let current = try frames(fixture)
          return current.contains { a in
            current.contains { b in
              a.id != b.id && abs(a.x - b.x) < 4
                && abs(b.y - (a.y + a.height) - Double(controller.settings.windowPadding * 2)) < 2
            }
          }
        }
        report.checks.append(
          Check(name: "stacking preserves the configured vertical gap", passed: true))
      }
      try require(
        try frames(sentinel).elementsEqual(excluded, by: { $0.matches($1) }),
        "Excluded sentinel remained unchanged")
      report.checks.append(Check(name: "excluded application never moved", passed: true))
      try await clickSessionSwitch(controller, running: false)
      report.checks.append(
        Check(name: "session pause restores windows with a recovery journal", passed: true))
      try require(
        controller.phase == .stopped && !controller.recoveryPending, "Pause completed recovery")
      try await eventually("Original frames restored") {
        let current = try frames(fixture)
        return original.allSatisfy { old in current.contains { $0.id == old.id && $0.matches(old) }
        }
      }
      report.checks.append(Check(name: "pause restores original native frames", passed: true))
      try require(
        try frames(sentinel).elementsEqual(excluded, by: { $0.matches($1) }),
        "Sentinel survives cleanup")
      try await clickSessionSwitch(controller, running: true)
      try require(controller.phase == .running, "Restart became ready")
      try await clickSessionSwitch(controller, running: false)
      try require(!controller.recoveryPending, "Restart restored original frames")
      report.checks.append(Check(name: "start-pause-start lifecycle", passed: true))
      try require(
        !FileManager.default.fileExists(
          atPath: controller.store.directory.appendingPathComponent("state/paneru/state.json").path),
        "Title-bearing engine snapshots are disabled")
      report.checks.append(Check(name: "no title-bearing engine state written", passed: true))
      report.status = "passed"
      report.detail =
        "Disposable fixture applications only. Focus timings include 100 ms reporting cadence; these are not input-to-photon benchmarks."
    } catch {
      if CommandLine.arguments.contains("--qa-fixed-content") {
        try? await controller.query().write(
          to: output.deletingLastPathComponent().appendingPathComponent("failed-state.json"))
      }
      await controller.pause()
      report.status = "failed"
      report.detail = error.localizedDescription
    }
    for app in owned { app.terminate() }
    try? write(report, to: output)
  }

  /// Native bodies may be clipped or parked. Width intent stays in Rust's bounds.
  static func requirePreservedWidths(
    from before: EngineState, to after: EngineState, excluding: Int32? = nil, message: String
  ) throws {
    try require(
      before.windows.allSatisfy { old in
        if old.windowID == excluding { return true }
        guard let width = old.frame?.width,
          let current = after.windows.first(where: { $0.windowID == old.windowID })?.frame?.width
        else { return false }
        return abs(current - width) < 4
      }, message)
  }

  static func frames(_ url: URL) throws -> [FixtureFrame] {
    try JSONDecoder().decode([FixtureFrame].self, from: Data(contentsOf: url))
  }

  static func settledFrames(_ url: URL) async throws -> [FixtureFrame] {
    var previous = try frames(url)
    var stable = 0
    for _ in 0..<60 {
      try await Task.sleep(for: .milliseconds(100))
      let current = try frames(url)
      let unchanged =
        current.count == previous.count
        && current.allSatisfy { frame in
          previous.contains { old in
            frame.id == old.id && abs(frame.x - old.x) < 1 && abs(frame.y - old.y) < 1
              && abs(frame.width - old.width) < 1 && abs(frame.height - old.height) < 1
          }
        }
      stable = unchanged ? stable + 1 : 0
      if stable >= 3 { return current }
      previous = current
    }
    throw VerificationError.failed("Native frames did not settle")
  }

  private static func changedFocus(_ url: URL, from id: UInt32?, timeout: TimeInterval) async throws
    -> Bool
  {
    let end = ProcessInfo.processInfo.systemUptime + timeout
    while ProcessInfo.processInfo.systemUptime < end {
      if try frames(url).first(where: \.focused)?.id != id { return true }
      try await Task.sleep(for: .milliseconds(40))
    }
    return false
  }

  static func eventually(_ name: String, condition: () async throws -> Bool) async throws {
    let end = ProcessInfo.processInfo.systemUptime + 6
    while ProcessInfo.processInfo.systemUptime < end {
      if (try? await condition()) == true { return }
      try await Task.sleep(for: .milliseconds(80))
    }
    throw VerificationError.failed(name)
  }

  static func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw VerificationError.failed(message) }
  }

  private static func write(_ report: Report, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: url, options: .atomic)
  }
}

enum VerificationError: Error, LocalizedError {
  case failed(String)
  var errorDescription: String? {
    if case .failed(let message) = self { return message }
    return nil
  }
}
