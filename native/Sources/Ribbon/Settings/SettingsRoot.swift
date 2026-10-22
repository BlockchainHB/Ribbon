import AppKit
import RibbonCore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
  case general, applications, layout, shortcuts
  var id: String { rawValue }
  var title: String {
    switch self {
    case .general: "General"
    case .applications: "Excluded Apps"
    case .layout: "Layout"
    case .shortcuts: "Shortcuts"
    }
  }
  var symbol: String {
    switch self {
    case .general: "gearshape"
    case .applications: "macwindow"
    case .layout: "rectangle.split.3x1"
    case .shortcuts: "keyboard"
    }
  }
  func matches(_ query: String) -> Bool {
    let terms: String
    switch self {
    case .general: terms = "window management accessibility permission recovery"
    case .applications: terms = "applications excluded ignored apps"
    case .layout:
      terms =
        "layout column widths preserve fill spacing gaps centering movement speed "
        + "scrolling trackpad modifiers"
    case .shortcuts: terms = "shortcuts keyboard keys bindings"
    }
    return query.isEmpty || (title + " " + terms).localizedCaseInsensitiveContains(query)
  }
}

struct SettingsRoot: View {
  @ObservedObject var controller: SessionController
  @Environment(\.scenePhase) private var scenePhase
  @State private var search = ""
  @State private var pane: SettingsPane? = {
    if CommandLine.arguments.contains("--qa-output")
      || CommandLine.arguments.contains("--ui-qa-output")
    {
      return .general
    }
    return SettingsPane(rawValue: UserDefaults.standard.string(forKey: "settingsPane") ?? "")
      ?? .general
  }()

  var body: some View {
    NavigationSplitView {
      List(selection: $pane) {
        ForEach(SettingsPane.allCases.filter { $0.matches(search) }) { item in
          NavigationLink(value: item) {
            Label(item.title, systemImage: item.symbol)
          }
        }
      }
      .listStyle(.sidebar)
      .toolbar(removing: .sidebarToggle)
      .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
      .searchable(text: $search, placement: .sidebar, prompt: "Search")
    } detail: {
      Group {
        switch pane ?? .general {
        case .general: GeneralSettings(controller: controller)
        case .applications: ApplicationSettings(controller: controller)
        case .layout: LayoutSettings(controller: controller)
        case .shortcuts: ShortcutSettings(controller: controller)
        }
      }
      .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle((pane ?? .general).title)
    }
    .navigationSplitViewStyle(.balanced)
    .toolbar(removing: .sidebarToggle)
    .tint(.blue)
    .frame(minWidth: 740, minHeight: 500)
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      while !Task.isCancelled {
        await controller.refreshPermission()
        if controller.permissionGranted { return }
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
      }
    }
    .onChange(of: controller.settings) { _, _ in controller.saveSettings() }
    .onChange(of: pane) { _, next in
      if !CommandLine.arguments.contains("--qa-output")
        && !CommandLine.arguments.contains("--ui-qa-output"), let next
      {
        UserDefaults.standard.set(next.rawValue, forKey: "settingsPane")
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    {
      _ in Task { await controller.refreshPermission() }
    }
    .alert(
      "Ribbon",
      isPresented: Binding(
        get: { controller.notice != nil }, set: { if !$0 { controller.notice = nil } }
      )
    ) {
      Button("OK") { controller.notice = nil }
    } message: {
      Text(controller.notice ?? "")
    }
  }
}
