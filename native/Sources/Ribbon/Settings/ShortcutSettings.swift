import AppKit
import RibbonCore
import SwiftUI

private struct ShortcutEdit: Identifiable {
  let id = UUID()
  let action: ShortcutAction
  let index: Int
}

struct ShortcutSettings: View {
  @ObservedObject var controller: SessionController
  @State private var search = ""

  @State private var editing: ShortcutEdit?
  @State private var reset = false
  @State private var error: String?
  private var editable: Bool { controller.phase == .stopped }
  private var actions: [ShortcutAction] {
    ShortcutAction.allCases.filter {
      search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
        || $0.group.localizedCaseInsensitiveContains(search)
    }
  }
  private var groups: [String] {
    actions.reduce(into: [String]()) { groups, action in
      if !groups.contains(action.group) { groups.append(action.group) }
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PreferencesSearchField(text: $search, accessibilityLabel: "Search shortcuts")
        .frame(width: 220)
        .padding(.horizontal, 20).padding(.top, 20)
        // Leave room for the native glass field outside its alignment rectangle.
        .padding(.bottom, 12)
      Form {
        ForEach(groups, id: \.self) { group in
          Section(group) {
            ForEach(actions.filter { $0.group == group }) { action in
              shortcutRow(action)
            }
          }
        }
      }.formStyle(.grouped)
        .overlay {
          if actions.isEmpty { ContentUnavailableView.search(text: search) }
        }
      HStack {
        Menu("Options") {
          Button("Restore All Default Shortcuts…") { reset = true }
            .disabled(!editable || controller.settings.shortcutOverrides.isEmpty)
        }.fixedSize()
        Spacer()
        if !editable {
          Text("Pause Ribbon to edit shortcuts.").font(.caption).foregroundStyle(.secondary)
        }
      }.padding([.horizontal, .bottom], 20)
    }
    .alert(
      "Cannot Change Shortcut",
      isPresented: Binding(
        get: { error != nil }, set: { if !$0 { error = nil } }
      )
    ) {
      Button("OK") { error = nil }
    } message: {
      Text(error ?? "")
    }
    .sheet(item: $editing) { target in
      ShortcutEditor(action: target.action, index: target.index, controller: controller)
    }
    .confirmationDialog("Restore all default shortcuts?", isPresented: $reset) {
      Button("Restore Defaults") {
        controller.settings.shortcutOverrides = [:]
        error = nil
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Custom assignments for all actions will be replaced.")
    }
  }

  private func shortcutRow(_ action: ShortcutAction) -> some View {
    let chords = controller.settings.shortcuts(for: action)
    return HStack(spacing: 16) {
      Text(action.title).help(action.detail ?? action.title)
      Spacer(minLength: 12)
      Button {
        editing = ShortcutEdit(action: action, index: 0)
      } label: {
        Text(
          chords.isEmpty
            ? "Record Shortcut" : chords.map(ShortcutDisplay.string).joined(separator: ", ")
        )
        .font(chords.isEmpty ? .body : .system(.body, design: .monospaced))
        .foregroundStyle(chords.isEmpty ? .secondary : .primary)
        .multilineTextAlignment(.trailing)
        .frame(minWidth: 100, alignment: .trailing)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain).disabled(!editable)
      .accessibilityLabel("Change shortcut for \(action.title)")
      .accessibilityValue(
        chords.isEmpty ? "Not set" : chords.map(ShortcutDisplay.accessible).joined(separator: ", ")
      )
      .help("Change shortcut; Control-click for alternate assignments and reset.")
    }
    .padding(.vertical, 6)
    .contextMenu { actionOptions(action) }
  }

  @ViewBuilder private func actionOptions(_ action: ShortcutAction) -> some View {
    let chords = controller.settings.shortcuts(for: action)
    Button("Add Shortcut…") { editing = ShortcutEdit(action: action, index: chords.count) }
      .disabled(!editable || chords.count >= 3)
    ForEach(chords.indices, id: \.self) { index in
      Button("Change \(ShortcutDisplay.string(chords[index]))…") {
        editing = ShortcutEdit(action: action, index: index)
      }.disabled(!editable)
      Button("Remove \(ShortcutDisplay.string(chords[index]))") {
        var next = chords
        next.remove(at: index)
        do { try controller.settings.setShortcuts(next, for: action) } catch {
          self.error = error.localizedDescription
        }
      }.disabled(!editable)
    }
    Button("Reset This Action") {
      var next = controller.settings
      next.shortcutOverrides.removeValue(forKey: action.rawValue)
      do {
        _ = try next.validated()
        controller.settings = next
        error = nil
      } catch { self.error = error.localizedDescription }
    }.disabled(!editable || controller.settings.shortcutOverrides[action.rawValue] == nil)
  }
}

private struct ShortcutEditor: View {
  let action: ShortcutAction
  let index: Int
  @ObservedObject var controller: SessionController
  @Environment(\.dismiss) private var dismiss
  @State private var candidate: ShortcutChord?
  @State private var held: ShortcutModifiers = []
  private var message: String? {
    guard let candidate else { return nil }
    do {
      var next = controller.settings
      try next.setShortcuts(replacing(candidate), for: action)
      return nil
    } catch { return error.localizedDescription }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(action.title).font(.headline)
      ShortcutCapture(
        displayValue: candidate.map(ShortcutDisplay.string) ?? (held.isEmpty ? "" : held.symbols),
        onChord: { candidate = $0 }, onModifiers: { held = $0 }, cancel: { dismiss() },
        confirm: commit
      )
      .frame(height: 28)
      .accessibilityLabel("Record shortcut for \(action.title)")
      if let message {
        Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("Press a key combination. Escape cancels.").font(.callout)
          .foregroundStyle(.secondary)
      }
      HStack {
        Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Save", action: commit).buttonStyle(.borderedProminent).keyboardShortcut(
          .defaultAction
        )
        .disabled(candidate == nil || message != nil || controller.phase != .stopped)
      }
    }.padding(20).frame(width: 360)
  }
  private func replacing(_ chord: ShortcutChord) -> [ShortcutChord] {
    var values = controller.settings.shortcuts(for: action)
    if values.indices.contains(index) { values[index] = chord } else { values.append(chord) }
    return values
  }
  private func commit() {
    guard let candidate, message == nil, controller.phase == .stopped else { return }
    do {
      try controller.settings.setShortcuts(replacing(candidate), for: action)
      dismiss()
    } catch { controller.notice = error.localizedDescription }
  }
}
