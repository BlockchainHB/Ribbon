import AppKit
import RibbonCore
import SwiftUI
import UniformTypeIdentifiers

private let columnType = UTType.utf8PlainText

struct OverviewView: View {
  @ObservedObject var controller: OverviewController
  @State private var hovered: Int32?
  @State private var dragged: Int32?
  @State private var destination: Int32?
  @State private var after = false

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 12) {
        if let snapshot = controller.snapshot {
          let rows = ordered(snapshot.displays).filter { !$0.columns.isEmpty }
          if rows.isEmpty {
            Text("No tiled windows").foregroundStyle(.secondary)
          } else {
            ForEach(rows) { display in
              ScrollView(.horizontal) {
                HStack(spacing: 8) {
                  ForEach(display.columns) { column in tile(column) }
                }
                .frame(minWidth: max(0, geometry.size.width - 32), alignment: .center)
              }
              .scrollIndicators(.hidden).frame(height: 140)
              .help(screenName(display.id))
            }
          }
          if let error = controller.error {
            Text(error).font(.caption).foregroundStyle(.secondary)
          }
        } else if let error = controller.error {
          Text(error).font(.caption).foregroundStyle(.secondary)
        } else {
          ProgressView().controlSize(.small)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(16)
    }
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    .tint(.blue)
    .onChange(of: controller.isDragging) { _, active in
      if !active {
        dragged = nil
        destination = nil
      }
    }
  }

  private func tile(_ column: OverviewSnapshot.Column) -> some View {
    let selected = column.contains(controller.selection ?? 0)
    return Button {
      controller.focus(column.id)
    } label: {
      VStack(spacing: 10) {
        Image(nsImage: controller.icon(column.representative?.bundleID))
          .resizable().frame(width: 80, height: 80)
          .overlay(alignment: .bottomTrailing) {
            if column.pairID != nil {
              Image(systemName: "link").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor).padding(5)
                .background(.regularMaterial, in: Circle())
                .accessibilityHidden(true)
            }
          }
        Text(column.representative?.appName ?? "Window")
          .font(.system(size: 14, weight: .medium)).lineLimit(1)
          .multilineTextAlignment(.center)
      }
      .frame(width: 112, height: 132)
      .background(
        selected
          ? Color.primary.opacity(0.1)
          : hovered == column.id ? Color.primary.opacity(0.05) : Color.clear,
        in: RoundedRectangle(cornerRadius: 16)
      )
      .overlay(alignment: after ? .trailing : .leading) {
        if destination == column.id {
          Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 10)
        }
      }
      .opacity(dragged == column.id && controller.isDragging ? 0.45 : 1)
      .contentShape(Rectangle())
    }
    .buttonStyle(OverviewTileStyle()).focusable(false)
    .onHover { hovered = $0 ? column.id : (hovered == column.id ? nil : hovered) }
    .accessibilityIdentifier("ribbon.column.\(column.id)")
    .accessibilityValue(selected ? "Selected" : column.pairID == nil ? "" : "Paired")
    .accessibilityLabel(column.windows.map { "\($0.appName), \($0.title)" }.joined(separator: "; "))
    .accessibilityHint("Focus this tile. Drag to change its order.")
    .help(
      column.windows.map(\.title).joined(separator: "\n")
        + (column.pairID == nil ? "" : "\nPaired · moves together")
    )
    .contextMenu {
      Button("Pair with Left") {
        controller.pairing(column.id, command: "pairid", argument: "west")
      }
      .disabled(!controller.canPair(column.id, right: false))
      Button("Pair with Right") {
        controller.pairing(column.id, command: "pairid", argument: "east")
      }
      .disabled(!controller.canPair(column.id, right: true))
      Button("Ungroup") { controller.pairing(column.id, command: "unpairid") }
        .disabled(column.pairID == nil)
      Divider()
      Menu("Arrange") {
        Button("½–½") { controller.pairing(column.id, command: "pairfitid", argument: "half") }
        Button("⅓–⅔") { controller.pairing(column.id, command: "pairfitid", argument: "third") }
        Button("⅔–⅓") { controller.pairing(column.id, command: "pairfitid", argument: "twothirds") }
      }
    }
    .onDrag {
      let token = controller.beginDrag()
      dragged = column.id
      let provider = ColumnProvider(object: String(column.id) as NSString)
      provider.onFinish = { [weak controller = controller] in
        Task { @MainActor in controller?.endDrag(token) }
      }
      return provider
    }
    .onDrop(
      of: [columnType],
      delegate: ColumnDrop(
        controller: controller, target: column.id, dragged: $dragged,
        destination: $destination, after: $after)
    )
  }

  private func ordered(_ displays: [OverviewSnapshot.Display]) -> [OverviewSnapshot.Display] {
    let ids = NSScreen.screens.map {
      ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        ?? 0
    }
    return displays.sorted {
      (ids.firstIndex(of: $0.id) ?? Int.max) < (ids.firstIndex(of: $1.id) ?? Int.max)
    }
  }

  private func screenName(_ id: UInt32) -> String {
    NSScreen.screens.first {
      ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        == id
    }?.localizedName ?? "Display"
  }

}

/// AppKit releases the provider when a drag finishes, including cancellation
/// outside the panel where no SwiftUI DropDelegate receives performDrop.
private final class ColumnProvider: NSItemProvider, @unchecked Sendable {
  var onFinish: (@Sendable () -> Void)?
  deinit { onFinish?() }
}

private struct ColumnDrop: DropDelegate {
  let controller: OverviewController
  let target: Int32
  @Binding var dragged: Int32?
  @Binding var destination: Int32?
  @Binding var after: Bool

  func validateDrop(info: DropInfo) -> Bool {
    guard let dragged else {
      controller.trace("validate \(target), source missing")
      return false
    }
    let allowed = controller.canMove(dragged, beside: target)
    controller.trace("validate \(dragged) -> \(target): \(allowed)")
    return allowed
  }
  func dropEntered(info: DropInfo) {
    controller.trace("entered \(target), source \(dragged ?? 0)")
    update(info)
  }
  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
    update(info)
    return DropProposal(operation: .move)
  }
  func dropExited(info: DropInfo) { if destination == target { destination = nil } }
  func performDrop(info: DropInfo) -> Bool {
    controller.trace("drop \(target), source \(dragged ?? 0)")
    defer { controller.endDrag() }
    guard validateDrop(info: info), let source = dragged else { return false }
    let insertAfter = info.location.x > 56
    dragged = nil
    destination = nil
    guard let provider = info.itemProviders(for: [columnType]).first else { return false }
    provider.loadObject(ofClass: NSString.self) { object, _ in
      guard object as? String == String(source) else { return }
      Task { @MainActor in
        await controller.move(source, beside: target, after: insertAfter, animate: true)
      }
    }
    return true
  }
  private func update(_ info: DropInfo) {
    guard validateDrop(info: info) else { return }
    destination = target
    after = info.location.x > 56
  }
}

private struct OverviewTileStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
      .animation(
        reduceMotion ? nil : .timingCurve(0.2, 0, 0, 1, duration: 0.12),
        value: configuration.isPressed)
  }
}
