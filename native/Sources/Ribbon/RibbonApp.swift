import AppKit
import ApplicationServices
import RibbonCore
import SwiftUI
import UniformTypeIdentifiers

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
    RibbonApp.main()
  }
}

@MainActor
struct RibbonApp: App {
  @NSApplicationDelegateAdaptor(RibbonDelegate.self) private var delegate
  @StateObject private var controller = SessionController.shared

  var body: some Scene {
    Window("Ribbon", id: "main") {
      ControlPanel(controller: controller)
        .task {
          await controller.refreshPermission()
          if CommandLine.arguments.contains("--qa-output") {
            await DesktopVerification.run(controller)
          }
        }
    }
    .defaultSize(width: 760, height: 760)
    .windowResizability(.contentSize)

    MenuBarExtra("Ribbon", systemImage: "rectangle.split.3x1") {
      RibbonMenu(controller: controller)
    }
  }
}

@MainActor
final class RibbonDelegate: NSObject, NSApplicationDelegate {
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

private struct RibbonMenu: View {
  @ObservedObject var controller: SessionController
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    Text("Ribbon · \(controller.phase.rawValue)")
    Button(controller.phase == .running ? "Pause & restore windows" : "Start Ribbon") {
      Task {
        if controller.phase == .running {
          await controller.pause()
        } else {
          await controller.start()
        }
      }
    }.disabled(controller.phase.busy)
    Button("Open Ribbon") {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }
    Button("Move window to next display") {
      Task { await controller.send(.nextDisplay) }
    }.disabled(controller.phase != .running || NSScreen.screens.count < 2)
    Divider()
    Button("Quit Ribbon") { NSApp.terminate(nil) }.keyboardShortcut("q")
  }
}

struct ControlPanel: View {
  @ObservedObject var controller: SessionController
  @State private var openingDemo = false
  private let tint = Color(red: 0.19, green: 0.42, blue: 0.34)

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      header
      if let notice = controller.notice {
        Label(notice, systemImage: "info.circle")
          .font(.callout).foregroundStyle(.secondary)
          .padding(14).frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
      }
      if !controller.permissionGranted { permissions }
      if controller.recoveryPending && controller.phase == .stopped {
        HStack {
          Label("A previous session can be restored.", systemImage: "arrow.uturn.backward")
          Spacer()
          Button("Restore windows") { Task { await controller.restorePreviousSession() } }
        }.font(.callout).padding(14).background(
          .orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
      }
      scope
      appearance
      shortcuts
      HStack {
        Text("Local beta · Powered by Paneru")
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("About & source") {
          let url = Bundle.main.resourceURL!.appendingPathComponent("README.html")
          NSWorkspace.shared.open(url)
        }.buttonStyle(.link).font(.caption)
      }
    }
    .padding(28).frame(width: 760)
    .tint(tint)
    .onChange(of: controller.settings) { _, _ in controller.saveSettings() }
  }

  private var header: some View {
    HStack(spacing: 16) {
      Image(systemName: "rectangle.split.3x1")
        .font(.system(size: 28, weight: .medium))
        .foregroundStyle(tint).frame(width: 58, height: 58)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
      VStack(alignment: .leading, spacing: 4) {
        Text("Ribbon").font(.system(size: 30, weight: .semibold))
        Text("Room for every window.").foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 8) {
        Label(
          controller.phase.rawValue,
          systemImage: controller.phase == .running ? "circle.fill" : "pause.circle"
        )
        .font(.caption.weight(.medium)).foregroundStyle(
          controller.phase == .running ? tint : .secondary)
        Button(controller.phase == .running ? "Pause & restore" : "Start Ribbon") {
          Task {
            if controller.phase == .running {
              await controller.pause()
            } else {
              await controller.start()
            }
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          controller.phase.busy || !controller.permissionGranted
            || controller.recoveryPending && controller.phase != .running)
      }
    }
  }

  private var permissions: some View {
    GroupBox {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: "hand.raised").font(.title2).foregroundStyle(tint)
        VStack(alignment: .leading, spacing: 8) {
          Text("Allow Ribbon to arrange windows").font(.headline)
          Text(
            "Enable Ribbon in System Settings → Privacy & Security → Accessibility. Ribbon runs locally and starts paused."
          )
          .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          HStack {
            Button("Open Accessibility Settings") { controller.openPermissionSettings() }
            Button("Check access") { Task { await controller.refreshPermission() } }
          }
        }
        Spacer(minLength: 0)
      }.padding(10)
    }
  }

  private var scope: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text("Managed applications").font(.headline)
          Spacer()
          Picker("Scope", selection: $controller.settings.scope) {
            Text("Demo windows").tag(ManagementScope.demo)
            Text("Selected apps").tag(ManagementScope.selected)
          }.pickerStyle(.segmented).frame(width: 270).labelsHidden()
            .disabled(controller.phase != .stopped)
        }
        if controller.settings.scope == .demo {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text("Try it with disposable windows")
              Text("Your other applications stay in place.").font(.callout).foregroundStyle(
                .secondary)
            }
            Spacer()
            Button("Open demo windows") {
              openingDemo = true
              Task {
                defer { openingDemo = false }
                do { try await controller.openDemo() } catch {
                  controller.notice = error.localizedDescription
                }
              }
            }.disabled(openingDemo || controller.phase.busy)
          }
        } else {
          ScrollView {
            VStack(spacing: 10) {
              ForEach(controller.apps) { app in
                Toggle(isOn: selection(app.id)) {
                  HStack {
                    if let icon = app.icon {
                      Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                    }
                    Text(app.name)
                    Spacer()
                  }
                }
              }
              ForEach(
                controller.settings.selectedBundleIDs.subtracting(Set(controller.apps.map(\.id)))
                  .sorted(), id: \.self
              ) { id in
                Toggle(id, isOn: selection(id)).font(.callout)
              }
            }.padding(2)
          }.frame(maxHeight: 145).disabled(controller.phase != .stopped)
          HStack {
            Button("Refresh apps") { controller.refreshApps() }
            Button("Add app…") { addApplication() }
            Spacer()
            Text("\(controller.settings.managedBundleIDs.count) selected")
              .font(.caption).foregroundStyle(.secondary)
          }.disabled(controller.phase != .stopped)
          Text("Pause Ribbon before changing which apps it manages.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }.padding(10)
    }
  }

  private func selection(_ id: String) -> Binding<Bool> {
    Binding(
      get: { controller.settings.selectedBundleIDs.contains(id) },
      set: { enabled in
        if enabled {
          controller.settings.selectedBundleIDs.insert(id)
        } else {
          controller.settings.selectedBundleIDs.remove(id)
        }
      })
  }

  private func addApplication() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier,
      RibbonSettings.validBundleID(id), id != RibbonSettings.appBundleID
    else { return }
    controller.settings.selectedBundleIDs.insert(id)
  }

  private var appearance: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        Text("Layout & motion").font(.headline)
        HStack {
          Text("Screen margins").frame(width: 130, alignment: .leading)
          Slider(
            value: Binding(
              get: { Double(controller.settings.gap) },
              set: { controller.settings.gap = Int($0) }), in: 0...40, step: 2)
          Text("\(controller.settings.gap) pt").monospacedDigit().frame(
            width: 48, alignment: .trailing)
        }
        Toggle("Keep the focused column centered", isOn: $controller.settings.centerFocused)
        HStack {
          Text("Trackpad swipe").frame(width: 130, alignment: .leading)
          Picker("Trackpad swipe", selection: $controller.settings.gestureFingers) {
            Text("Modifier scroll only").tag(0)
            Text("3 fingers").tag(3)
            Text("4 fingers").tag(4)
          }.labelsHidden()
        }
        Text(
          "Control–Option + horizontal scroll always works. Multi-finger swipes must use a gesture that macOS isn’t also using for Spaces."
        )
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }.padding(10).disabled(controller.phase.busy)
    }
  }

  private var shortcuts: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        Text("Move through your strip").font(.headline)
        HStack(spacing: 24) {
          shortcut("Focus", "⌃⌥ ← →")
          shortcut("Width", "⌃⌥ R")
          shortcut("Center", "⌃⌥ C")
          shortcut("Stack", "⌃⌥ ]")
          shortcut("Pause", "⌃⌥ Q")
        }
        Text(
          "Add Shift to the arrows to reorder. Control–Option–Shift–] pulls a window out of a stack."
        )
        .font(.caption).foregroundStyle(.secondary)
        Label(
          "Each display has its own strip. Control–Option–N moves a window to the next display and keeps its width proportion.",
          systemImage: "display.2"
        )
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func shortcut(_ title: String, _ keys: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(keys).font(.system(.callout, design: .monospaced).weight(.medium))
    }
  }
}
