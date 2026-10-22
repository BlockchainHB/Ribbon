import AppKit
import SwiftUI

/// Native search field with its standard search, cancel and focus behavior.
struct PreferencesSearchField: NSViewRepresentable {
  @Binding var text: String
  var accessibilityLabel = "Search"
  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.controlSize = .regular
    field.font = .systemFont(ofSize: NSFont.systemFontSize)
    field.textColor = .labelColor
    field.placeholderAttributedString = NSAttributedString(
      string: "Search", attributes: [.foregroundColor: NSColor.secondaryLabelColor])
    field.delegate = context.coordinator
    field.target = context.coordinator
    field.action = #selector(Coordinator.searchChanged(_:))
    field.sendsSearchStringImmediately = true
    field.sendsWholeSearchString = false
    field.setAccessibilityLabel(accessibilityLabel)
    return field
  }
  func updateNSView(_ field: NSSearchField, context: Context) {
    context.coordinator.text = $text
    if field.stringValue != text { field.stringValue = text }
  }
  func sizeThatFits(
    _ proposal: ProposedViewSize, nsView: NSSearchField, context: Context
  ) -> CGSize? {
    CGSize(width: proposal.width ?? 220, height: nsView.intrinsicContentSize.height)
  }
  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var text: Binding<String>
    init(text: Binding<String>) { self.text = text }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSSearchField else { return }
      searchChanged(field)
    }
    @objc func searchChanged(_ field: NSSearchField) {
      text.wrappedValue = field.stringValue
    }
  }
}
