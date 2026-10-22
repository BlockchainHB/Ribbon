import AppKit
import RibbonCore
import SwiftUI
import UniformTypeIdentifiers

struct ApplicationSettings: View {
  @ObservedObject var controller: SessionController
  @State private var search = ""
  private var editable: Bool { controller.phase == .stopped }
  private var displayedApps: [RunningApp] {
    let existing = Set(controller.apps.map(\.id))
    let saved = controller.settings.excludedBundleIDs.subtracting(existing).map { id in
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
      return RunningApp(
        id: id, name: url?.deletingPathExtension().lastPathComponent ?? id,
        icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) })
    }
    return (controller.apps + saved).filter {
      search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PreferencesSearchField(text: $search, accessibilityLabel: "Search applications").frame(
        width: 220
      )
      .padding(.horizontal, 20).padding(.top, 20)
      .padding(.bottom, 12)
      Form {
        Section {
          ForEach(displayedApps) { app in
            HStack {
              Label {
                Text(app.name)
              } icon: {
                if let icon = app.icon {
                  Image(nsImage: icon).resizable().frame(width: 20, height: 20).accessibilityHidden(
                    true)
                } else {
                  Image(systemName: "app").accessibilityHidden(true)
                }
              }
              Spacer()
              Toggle(app.name, isOn: selection(app.id))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                .disabled(!editable).accessibilityLabel(
                  "Exclude \(app.name) from window management")
            }
          }
        } header: {
          Text("Exclude from window management")
        } footer: {
          Text("Ribbon manages all open apps automatically. Turn on an app here to exclude it.")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }.formStyle(.grouped)
        .overlay {
          if displayedApps.isEmpty { ContentUnavailableView.search(text: search) }
        }
      HStack {
        Button("Exclude Application…", action: addApplication).disabled(!editable)
        Spacer()
        if !editable {
          Text("Pause Ribbon to change exclusions.").font(.caption).foregroundStyle(.secondary)
        }
      }.padding([.horizontal, .bottom], 20)
    }
    .onAppear { controller.refreshApps() }
    .onReceive(
      NSWorkspace.shared.notificationCenter.publisher(
        for: NSWorkspace.didLaunchApplicationNotification)
    ) {
      _ in controller.refreshApps()
    }
    .onReceive(
      NSWorkspace.shared.notificationCenter.publisher(
        for: NSWorkspace.didTerminateApplicationNotification)
    ) {
      _ in controller.refreshApps()
    }

  }
  private func selection(_ id: String) -> Binding<Bool> {
    Binding(
      get: { controller.settings.excludedBundleIDs.contains(id) },
      set: { selected in
        if selected {
          controller.settings.excludedBundleIDs.insert(id)
        } else {
          controller.settings.excludedBundleIDs.remove(id)
        }
      })
  }
  private func addApplication() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier,
      RibbonSettings.validBundleID(id),
      ![RibbonSettings.appBundleID, "com.apple.systempreferences"].contains(id)
    else { return }
    controller.settings.excludedBundleIDs.insert(id)
  }
}
