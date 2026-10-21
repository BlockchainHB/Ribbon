import AppKit
import ApplicationServices
import RibbonCore
import SwiftUI

enum SessionPhase: String {
  case stopped = "Paused"
  case starting = "Starting…"
  case running = "Running"
  case stopping = "Restoring windows…"
  var busy: Bool { self == .starting || self == .stopping }
}

struct RunningApp: Identifiable {
  let id: String
  let name: String
  let icon: NSImage?
}

@MainActor
final class SessionController: ObservableObject {
  static let shared = SessionController()
  @Published var settings = RibbonSettings()
  @Published private(set) var phase: SessionPhase = .stopped
  @Published private(set) var permissionGranted = false
  @Published private(set) var apps: [RunningApp] = []
  @Published var notice: String?
  @Published private(set) var recoveryPending = false
  let store: LocalStore
  private let runner = CommandRunner()
  private var engine: Process?
  private var expectedExit = false
  private var commandInFlight = false
  private var restorationInFlight = false

  init(store: LocalStore? = nil) {
    if let store {
      self.store = store
    } else if let index = CommandLine.arguments.firstIndex(of: "--qa-output"),
      CommandLine.arguments.indices.contains(index + 1)
    {
      self.store = LocalStore(
        directory: URL(fileURLWithPath: CommandLine.arguments[index + 1])
          .deletingLastPathComponent().appendingPathComponent("session", isDirectory: true))
    } else {
      self.store = .standard
    }
    recoveryPending = FileManager.default.fileExists(
      atPath: self.store.directory.appendingPathComponent("recovery.json").path)
    do {
      if let saved = try self.store.read(RibbonSettings.self, from: "settings.json") {
        settings = try saved.validated()
      }
      _ = try self.store.read(RecoveryJournal.self, from: "recovery.json")?.validated()
    } catch {
      notice = "Saved settings or recovery data could not be read. \(error.localizedDescription)"
    }
    refreshApps()
  }

  var engineURL: URL {
    Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ribbon-engine")
  }
  var fixtureURL: URL { Bundle.main.resourceURL!.appendingPathComponent("Ribbon Demo.app") }
  var engineEnvironment: [String: String] {
    [
      "PANERU_MACH_SERVICE": "dev.ribbon.engine.\(getuid())",
      "PANERU_CONFIG": store.directory.appendingPathComponent("engine.toml").path,
      "XDG_CONFIG_HOME": store.directory.appendingPathComponent("config").path,
      "XDG_STATE_HOME": store.directory.appendingPathComponent("state").path,
      "RIBBON_MANAGED_APPS": settings.managedBundleIDs.sorted().joined(separator: ","),
      "RIBBON_PARENT_PID": String(getpid()), "RUST_LOG": "error",
    ]
  }

  func refreshApps() {
    var seen = Set<String>()
    apps = NSWorkspace.shared.runningApplications.compactMap { app in
      guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
        ![RibbonSettings.appBundleID, "com.apple.systempreferences"].contains(id),
        seen.insert(id).inserted
      else { return nil }
      return RunningApp(id: id, name: app.localizedName ?? id, icon: app.icon)
    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  func refreshPermission() async {
    guard FileManager.default.isExecutableFile(atPath: engineURL.path) else {
      notice = "The bundled engine is missing. Rebuild the app using scripts/build-app.sh."
      permissionGranted = false
      return
    }
    do {
      let result = try await runner.run(engineURL, arguments: ["check-permission"], timeout: 2)
      permissionGranted =
        AXIsProcessTrusted() && result.status == 0
        && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    } catch { permissionGranted = false }
  }

  func openPermissionSettings() {
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }

  func saveSettings() {
    guard !phase.busy else { return }
    do {
      _ = try settings.validated()
      try store.write(settings, to: "settings.json")
      if phase == .running { try writeEngineConfiguration() }
    } catch { notice = error.localizedDescription }
  }

  private func writeEngineConfiguration() throws {
    try store.prepare()
    try settings.engineConfiguration().write(
      to: store.directory.appendingPathComponent("engine.toml"),
      atomically: true, encoding: .utf8)
  }

  func openDemo(report: URL? = nil, dualDisplays: Bool = false) async throws {
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    if let report { config.arguments = ["--report", report.path] }
    if dualDisplays { config.arguments.append("--dual-displays") }
    _ = try await NSWorkspace.shared.openApplication(at: fixtureURL, configuration: config)
    refreshApps()
  }

  func start() async {
    guard phase == .stopped, engine == nil else { return }
    guard !recoveryPending else {
      notice = "Restore the previous session before starting a new one."
      return
    }
    notice = nil
    phase = .starting
    await refreshPermission()
    guard permissionGranted else {
      phase = .stopped
      return
    }
    guard !settings.managedBundleIDs.isEmpty else {
      notice = "Choose at least one application to manage."
      phase = .stopped
      return
    }
    do {
      try writeEngineConfiguration()
      if settings.scope == .demo,
        ApplicationIdentity.running(in: [RibbonSettings.fixtureBundleID]).isEmpty
      {
        try await openDemo()
        try await Task.sleep(for: .milliseconds(300))
      }
      let identities = ApplicationIdentity.running(in: settings.managedBundleIDs)
      let windows = try await AccessibilityWorkspace.snapshot(identities)
      try store.write(
        RecoveryJournal(windows: windows, managedBundleIDs: settings.managedBundleIDs),
        to: "recovery.json")
      recoveryPending = true
      let child = Process()
      child.executableURL = engineURL
      child.arguments = ["launch"]
      child.environment = ProcessInfo.processInfo.environment.merging(engineEnvironment) { _, new in
        new
      }
      child.standardOutput = FileHandle.nullDevice
      child.standardError = FileHandle.nullDevice
      if CommandLine.arguments.contains("--qa-output") {
        let log = store.directory.appendingPathComponent("engine.log")
        FileManager.default.createFile(
          atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: log)
        child.standardOutput = handle
        child.standardError = handle
        child.environment?["RUST_LOG"] =
          "warn,paneru::ecs::focus=trace,paneru::manager::windows=debug,paneru::commands=debug"
      }
      child.terminationHandler = { [weak self] process in
        Task { @MainActor in self?.engineExited(process) }
      }
      expectedExit = false
      try child.run()
      engine = child
      for _ in 0..<15 {
        guard child.isRunning else { throw SessionError.engineExited }
        if let result = try? await runner.run(
          engineURL, arguments: ["query", "state", "--json"],
          environment: engineEnvironment, timeout: 0.6),
          result.status == 0,
          (try? JSONSerialization.jsonObject(with: Data(result.output.utf8))) != nil
        {
          phase = .running
          return
        }
        try await Task.sleep(for: .milliseconds(100))
      }
      throw CommandError.timedOut
    } catch {
      expectedExit = true
      _ = await stopOwnedEngine()
      phase = engine?.isRunning == true ? .running : .stopped
      notice = "Could not start Ribbon. \(error.localizedDescription)"
    }
  }

  private func engineExited(_ child: Process) {
    guard engine === child else { return }
    engine = nil
    if !expectedExit {
      phase = .stopped
      if child.terminationStatus == 0 {
        phase = .stopping
        Task {
          await restorePreviousSession()
          phase = .stopped
        }
      } else {
        notice = "The engine stopped. Your recovery record is available below."
      }
    }
  }

  func pause() async {
    guard !phase.busy else { return }
    phase = .stopping
    expectedExit = true
    guard await stopOwnedEngine() else {
      notice =
        "The engine has not exited. Recovery is waiting so two processes cannot move your windows at once."
      phase = .running
      return
    }
    await restorePreviousSession()
    phase = .stopped
  }

  private func stopOwnedEngine() async -> Bool {
    guard let child = engine else { return true }
    if child.isRunning {
      _ = try? await runner.run(
        engineURL, arguments: ["send-cmd", "quit"],
        environment: engineEnvironment, timeout: 1)
    }
    for _ in 0..<25 {
      if !child.isRunning {
        engine = nil
        return true
      }
      try? await Task.sleep(for: .milliseconds(100))
    }
    if child.isRunning { child.interrupt() }
    for _ in 0..<25 {
      if !child.isRunning {
        engine = nil
        return true
      }
      try? await Task.sleep(for: .milliseconds(100))
    }
    if child.isRunning { kill(child.processIdentifier, SIGKILL) }
    for _ in 0..<10 {
      if !child.isRunning {
        engine = nil
        return true
      }
      try? await Task.sleep(for: .milliseconds(100))
    }
    return false
  }

  func restorePreviousSession() async {
    guard engine?.isRunning != true, !restorationInFlight,
      phase == .stopping || phase == .stopped
    else { return }
    restorationInFlight = true
    let manualRecovery = phase == .stopped
    if manualRecovery { phase = .stopping }
    defer {
      restorationInFlight = false
      if manualRecovery { phase = .stopped }
    }
    do {
      guard let journal = try store.read(RecoveryJournal.self, from: "recovery.json")?.validated()
      else {
        recoveryPending = false
        return
      }
      guard AXIsProcessTrusted() else {
        notice = "Ribbon needs Accessibility access to restore the previous window positions."
        return
      }
      let apps = ApplicationIdentity.running(in: journal.managedBundleIDs)
      let top = NSScreen.screens.first?.frame.maxY ?? 0
      let displays = NSScreen.screens.map { screen in
        CGRect(
          x: screen.visibleFrame.minX, y: top - screen.visibleFrame.maxY,
          width: screen.visibleFrame.width, height: screen.visibleFrame.height)
      }
      let result = await AccessibilityWorkspace.restore(
        journal, applications: apps, displays: displays)
      if result.failed == 0 {
        try store.remove("recovery.json")
        recoveryPending = false
      } else {
        notice =
          "\(result.failed) window(s) did not accept their original position. The recovery record is retained."
      }
    } catch { notice = "Recovery data could not be read. \(error.localizedDescription)" }
  }

  func send(_ command: EngineCommand) async {
    guard phase == .running, !commandInFlight else { return }
    commandInFlight = true
    defer { commandInFlight = false }
    do {
      let result = try await runner.run(
        engineURL, arguments: command.arguments,
        environment: engineEnvironment, timeout: 2)
      if result.status != 0 { throw SessionError.commandFailed }
    } catch { notice = error.localizedDescription }
  }

  func query() async throws -> Data {
    let result = try await runner.run(
      engineURL, arguments: ["query", "state", "--json"],
      environment: engineEnvironment, timeout: 2)
    guard result.status == 0 else { throw SessionError.commandFailed }
    return Data(result.output.utf8)
  }
}

enum SessionError: Error, LocalizedError {
  case engineExited, commandFailed
  var errorDescription: String? {
    switch self {
    case .engineExited: return "The window engine exited before becoming ready."
    case .commandFailed: return "The window engine could not accept that command."
    }
  }
}
