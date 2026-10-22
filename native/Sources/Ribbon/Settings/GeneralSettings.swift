import RibbonCore
import SwiftUI

struct GeneralSettings: View {
  @ObservedObject var controller: SessionController
  var body: some View {
    Form {
      Section {
        LabeledContent("Window management") {
          Toggle(
            "Enable Ribbon",
            isOn: Binding(
              get: { controller.phase == .running || controller.phase == .starting },
              set: { _ in Task { await controller.toggleSession() } }
            )
          )
          .labelsHidden().toggleStyle(.switch).controlSize(.mini)
          .disabled(!controller.canToggleSession)
          .accessibilityLabel("Enable Ribbon")
        }
        if !controller.permissionGranted {
          Text("Allow Ribbon in System Settings to manage windows.")
            .font(.caption).foregroundStyle(.secondary)
        }
        if controller.phase.busy {
          ProgressView(controller.phase.rawValue).controlSize(.small)
        }
      }
      Section {
        LabeledContent("Accessibility") {
          if controller.permissionGranted {
            Text("Allowed").foregroundStyle(.secondary)
          } else {
            Button("Open System Settings…") { controller.openPermissionSettings() }
          }
        }
      }
      if controller.recoveryPending && controller.phase == .stopped {
        Section {
          LabeledContent("Previous session") {
            Button("Restore Window Positions") {
              Task { await controller.restorePreviousSession() }
            }
          }
        }
      }
    }.formStyle(.grouped)
  }
}
