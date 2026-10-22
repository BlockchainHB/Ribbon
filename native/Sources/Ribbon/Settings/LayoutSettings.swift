import RibbonCore
import SwiftUI

struct LayoutSettings: View {
  @ObservedObject var controller: SessionController
  private let modifiers: [(String, ShortcutModifiers)] = [
    ("Control", .control), ("Option", .option), ("Shift", .shift), ("Command", .command),
  ]
  var body: some View {
    Form {
      Section("Windows") {
        LabeledContent("Column widths") {
          Picker("Column widths", selection: $controller.settings.widthPolicy) {
            Text("Preserve widths").tag(WindowWidthPolicy.preserve)
            Text("Fill available space").tag(WindowWidthPolicy.fill)
          }.labelsHidden().fixedSize()
            .help(
              "Expand columns when the strip fits. Wider strips keep their preferred widths and scroll."
            )
        }
        LabeledContent("Spacing") {
          HStack(spacing: 8) {
            Slider(
              value: Binding(
                get: { Double(controller.settings.gap) },
                set: { controller.settings.gap = Int(($0 / 2).rounded()) * 2 }
              ), in: 0...40
            )
            .accessibilityLabel("Window spacing")
            .help(
              "Horizontal spacing and gaps between stacked windows. Tiles fill the usable screen height."
            )
            Text("\(controller.settings.gap) pt").monospacedDigit().frame(
              width: 40, alignment: .trailing)
          }.frame(width: 200)
        }
        Toggle("Center focused column", isOn: $controller.settings.centerFocused)
          .toggleStyle(.switch).controlSize(.mini)
      }
      Section {
        LabeledContent("Speed") {
          Slider(
            value: Binding(
              get: { Double(controller.settings.animationSpeed) },
              set: { controller.settings.animationSpeed = Int($0.rounded()) }
            ), in: 8...24
          )
          .accessibilityLabel("Movement speed")
          .frame(width: 200).disabled(controller.reduceMotion)
        }
      } header: {
        Text("Movement")
      } footer: {
        if controller.reduceMotion {
          Text("Reduce Motion is enabled in System Settings.")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      Section("Scrolling") {
        LabeledContent("Modifier keys") {
          Menu {
            ForEach(modifiers, id: \.0) { name, modifier in
              Toggle(
                name,
                isOn: Binding(
                  get: { controller.settings.scrollModifiers.contains(modifier) },
                  set: { enabled in
                    var next = controller.settings.scrollModifiers
                    if enabled { next.insert(modifier) } else { next.remove(modifier) }
                    if !next.isEmpty { controller.settings.scrollModifiers = next }
                  }))
            }
          } label: {
            Text(controller.settings.scrollModifiers.symbols)
          }.fixedSize().accessibilityLabel("Scroll modifier keys")
        }
        LabeledContent("Trackpad swipe") {
          Picker("Trackpad swipe", selection: $controller.settings.gestureFingers) {
            Text("Off").tag(0)
            Text("Three fingers").tag(3)
            Text("Four fingers").tag(4)
          }.labelsHidden().fixedSize()
        }
      }
    }.formStyle(.grouped).disabled(controller.phase.busy)
  }
}
