import AppKit
import ApplicationServices
import RibbonCore
import SwiftUI

@main
@MainActor
enum RibbonEntry {
  static func main() {
    if CommandLine.arguments.contains("--print-config") {
      do { print(try RibbonSettings().engineConfiguration()) } catch {
        fputs("\(error)\n", stderr)
        exit(1)
      }
      return
    }
    if CommandLine.arguments.contains("--watchdog-probe") {
      guard AXIsProcessTrusted() else { exit(77) }
      let child = Process()
      child.executableURL = Bundle.main.bundleURL.appendingPathComponent(
        "Contents/MacOS/ribbon-engine")
      child.arguments = ["launch"]
      child.environment = ProcessInfo.processInfo.environment.merging([
        "RIBBON_PARENT_PID": String(getpid()),
        "RIBBON_MANAGED_APPS": "dev.ribbon.watchdog-probe",
        "RIBBON_MANAGEMENT_SCOPE": "selected", "RIBBON_EXCLUDED_APPS": "",
        "PANERU_MACH_SERVICE": "dev.ribbon.watchdog.\(getpid())",
        "RUST_LOG": "error",
      ]) { _, new in new }
      child.standardOutput = FileHandle.nullDevice
      child.standardError = FileHandle.nullDevice
      do {
        try child.run()
        var ready = false
        for _ in 0..<20 where child.isRunning {
          let query = Process()
          query.executableURL = child.executableURL
          query.arguments = ["query", "state", "--json"]
          query.environment = child.environment
          query.standardOutput = FileHandle.nullDevice
          query.standardError = FileHandle.nullDevice
          try query.run()
          query.waitUntilExit()
          if query.terminationStatus == 0 {
            ready = true
            break
          }
          Thread.sleep(forTimeInterval: 0.1)
        }
        guard ready else {
          if child.isRunning { child.interrupt() }
          exit(1)
        }
        FileHandle.standardOutput.write(Data("\(child.processIdentifier)\n".utf8))
      } catch { exit(1) }
      return
    }
    if CommandLine.arguments.contains("--ui-qa-output"),
      let index = CommandLine.arguments.firstIndex(of: "--ui-qa-appearance"),
      CommandLine.arguments.indices.contains(index + 1)
    {
      NSApplication.shared.appearance = NSAppearance(
        named: CommandLine.arguments[index + 1] == "light" ? .aqua : .darkAqua)
    }
    RibbonApp.main()
  }
}

@MainActor
struct RibbonApp: App {
  @NSApplicationDelegateAdaptor(RibbonDelegate.self) private var delegate
  @StateObject private var controller = SessionController.shared

  var body: some Scene {
    Window("Ribbon", id: "main") {
      RibbonSettingsWindow(controller: controller, delegate: delegate)
        .task {
          await controller.refreshPermission()
          if CommandLine.arguments.contains("--qa-output") {
            await DesktopVerification.run(controller, statusMenu: delegate.statusMenu)
          }
        }
    }
    .defaultSize(width: 800, height: 560)
    .windowResizability(.contentMinSize)
    .commands {
      CommandGroup(replacing: .appSettings) { SettingsMenuCommand() }
      CommandGroup(replacing: .appInfo) {
        Button("About Ribbon") { showRibbonAbout() }
      }
    }
  }
}

@MainActor
final class RibbonDelegate: NSObject, NSApplicationDelegate {
  private(set) var statusMenu: RibbonStatusMenu?
  private var overview: OverviewController?
  var openSettings: () -> Void = {}

  func applicationDidFinishLaunching(_ notification: Notification) {
    let overview = OverviewController(session: .shared)
    self.overview = overview
    let menu = RibbonStatusMenu(
      controller: .shared, openOverview: { overview.toggle() },
      openSettings: { [weak self] in self?.openSettings() })
    menu.install()
    statusMenu = menu
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let controller = SessionController.shared
    Task {
      for _ in 0..<100 where controller.phase.busy {
        try? await Task.sleep(for: .milliseconds(100))
      }
      guard !controller.phase.busy else {
        controller.notice = "Ribbon is still finishing a window operation."
        sender.reply(toApplicationShouldTerminate: false)
        return
      }
      await controller.pause()
      sender.reply(toApplicationShouldTerminate: controller.phase == .stopped)
    }
    return .terminateLater
  }
}

private struct RibbonSettingsWindow: View {
  @ObservedObject var controller: SessionController
  let delegate: RibbonDelegate
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    SettingsRoot(controller: controller).onAppear {
      let action = openWindow
      delegate.openSettings = {
        action(id: "main")
        NSApp.activate(ignoringOtherApps: true)
      }
    }
  }
}

private struct SettingsMenuCommand: View {
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    Button("Settings…") {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }.keyboardShortcut(",", modifiers: .command)
  }
}

@MainActor
func showRibbonAbout() {
  let credits = NSMutableAttributedString()
  for (label, file) in [
    ("Acknowledgments", "README.html"), ("Open-Source Licenses", "DependencyLicenses.txt"),
  ] {
    guard let url = Bundle.main.resourceURL?.appendingPathComponent(file) else { continue }
    if credits.length > 0 { credits.append(NSAttributedString(string: "\n")) }
    credits.append(NSAttributedString(string: label, attributes: [.link: url]))
  }
  NSApp.orderFrontStandardAboutPanel(options: [
    .applicationIcon: RibbonBrand.applicationIcon, .credits: credits,
  ])
  NSApp.activate(ignoringOtherApps: true)
}
