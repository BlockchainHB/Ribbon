import AppKit
import Combine
import RibbonCore
import SwiftUI

@MainActor
final class OverviewController: ObservableObject {
  @Published private(set) var snapshot: OverviewSnapshot?
  @Published private(set) var busy = false
  @Published private(set) var isDragging = false
  @Published private(set) var error: String?
  @Published var selection: Int32?
  private var icons: [String: NSImage] = [:]
  private var dragToken: UUID?
  private let session: SessionController
  private let runner = CommandRunner()
  private var panel: OverviewPanel?
  private var refreshTask: Task<Void, Never>?
  private var presentationTask: Task<Void, Never>?
  private var notification: NSObjectProtocol?
  private var phaseObservation: AnyCancellable?
  private var keyMonitor: Any?
  private var presentation: UUID?
  private var debugEvents: [String] = []

  func trace(_ event: String) {
    guard CommandLine.arguments.contains("--qa-output") else { return }
    debugEvents.append(event)
    if debugEvents.count > 200 { debugEvents.removeFirst() }
    try? session.store.write(debugEvents, to: "overview-events.json")
  }

  init(session: SessionController) {
    self.session = session
    notification = DistributedNotificationCenter.default().addObserver(
      forName: .init("dev.ribbon.show-overview"), object: String(getpid()), queue: .main
    ) { [weak self] _ in Task { @MainActor in self?.toggle() } }
    phaseObservation = session.$phase.dropFirst().sink { [weak self] phase in
      if phase != .running { self?.hide() }
    }
  }

  func toggle() {
    if presentation != nil {
      hide()
      return
    }
    guard session.phase == .running else { return }
    let token = UUID()
    presentation = token
    error = nil
    presentationTask = Task { [weak self] in
      guard let self else { return }
      // Size from the engine response before showing. Avoid a small spinner
      // panel jumping wider a frame later on every keyboard invocation.
      do {
        let initial = try await read()
        guard presentation == token, !Task.isCancelled else { return }
        snapshot = initial
        selection = initial.focused ?? initial.displays.flatMap(\.columns).first?.id
      } catch {
        guard presentation == token, !Task.isCancelled else { return }
        snapshot = nil
        self.error = "The window list could not be refreshed."
      }
      let panel = panel ?? makePanel()
      self.panel = panel
      position(panel)
      panel.makeKeyAndOrderFront(nil)
      keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, self.panel?.isKeyWindow == true else { return event }
        return self.handleKey(event) ? nil : event
      }
      refreshTask = Task { [weak self] in
        guard let self else { return }
        while !Task.isCancelled, panel.isVisible {
          do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
          if !busy { await refresh() }
        }
      }
    }
  }

  func hide() {
    presentation = nil
    presentationTask?.cancel()
    presentationTask = nil
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
    dragToken = nil
    isDragging = false
    refreshTask?.cancel()
    refreshTask = nil
    panel?.orderOut(nil)
  }

  private func makePanel() -> OverviewPanel {
    let panel = OverviewPanel(
      contentRect: .zero, styleMask: [.nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: false)
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.title = "Arrange Windows"
    panel.contentView = OverviewHostingView(rootView: OverviewView(controller: self))
    panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
    panel.onResign = { [weak self] in
      let presentation = self?.presentation
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(150))
        guard let self, self.presentation == presentation, self.dragToken == nil,
          self.panel?.isKeyWindow == false
        else { return }
        self.hide()
      }
    }
    return panel
  }

  private func position(_ panel: NSPanel) {
    let screen =
      NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
      ?? NSScreen.main
    guard let screen else { return }
    let area = screen.visibleFrame
    let columns = snapshot?.displays.map { $0.columns.count }.max() ?? 2
    let width = min(max(280, CGFloat(columns * 120 + 24)), area.width - 48)
    let rows = max(
      1, snapshot?.displays.filter { !$0.columns.isEmpty }.count ?? NSScreen.screens.count)
    let height = min(CGFloat(rows * 152 + 20), area.height - 48)
    panel.setFrame(
      CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height),
      display: true)
  }

  private func read() async throws -> OverviewSnapshot {
    let result = try await runner.run(
      session.engineURL, arguments: ["overview-state"], environment: session.engineEnvironment,
      timeout: 2)
    guard result.status == 0 else { throw SessionError.commandFailed }
    return try JSONDecoder().decode(OverviewSnapshot.self, from: Data(result.output.utf8))
  }

  private func refresh() async {
    do {
      let next = try await read()
      guard panel?.isVisible == true, !Task.isCancelled else { return }
      let initial = snapshot == nil
      snapshot = next
      if initial, let panel { position(panel) }
      if selection == nil || next.columns(containing: selection!) == nil {
        selection = next.focused ?? next.displays.flatMap(\.columns).first?.id
      }
      error = nil
    } catch {
      guard !Task.isCancelled else { return }
      self.error = "The window list could not be refreshed."
    }
  }

  func icon(_ bundle: String?) -> NSImage {
    let key = bundle ?? ""
    if let image = icons[key] { return image }
    let image: NSImage
    if let bundle, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
      image = NSWorkspace.shared.icon(forFile: url.path)
    } else {
      image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)!
    }
    icons[key] = image
    return image
  }

  func focus(_ id: Int32) {
    trace("focus \(id)")
    guard !busy, session.phase == .running else { return }
    hide()
    Task {
      _ = try? await runner.run(
        session.engineURL, arguments: ["send-cmd", "window", "focusid", String(id)],
        environment: session.engineEnvironment, timeout: 2)
    }
  }

  func canMove(_ source: Int32, beside target: Int32) -> Bool {
    guard !busy, source != target, let columns = snapshot?.columns(containing: source) else {
      return false
    }
    return columns.contains { $0.contains(target) }
      && snapshot?.movementRange(containing: source) != snapshot?.movementRange(containing: target)
  }

  func beginDrag() -> UUID {
    trace("begin drag")
    let token = UUID()
    dragToken = token
    isDragging = true
    return token
  }
  func endDrag(_ token: UUID? = nil) {
    trace("end drag")
    guard token == nil || token == dragToken else { return }
    dragToken = nil
    isDragging = false
    if panel?.isVisible == true { panel?.makeKey() }
  }

  func move(_ source: Int32, beside target: Int32, after: Bool, animate: Bool = false) async {
    trace("move \(source) beside \(target) after \(after)")
    guard canMove(source, beside: target), session.phase == .running else { return }
    busy = true
    defer { busy = false }
    do {
      let result = try await runner.run(
        session.engineURL,
        arguments: [
          "send-cmd", "window", "reorder", String(source), String(target),
          after ? "after" : "before",
        ],
        environment: session.engineEnvironment, timeout: 2)
      guard result.status == 0 else { throw SessionError.commandFailed }
      // The command is asynchronous. Display only engine-confirmed order,
      // including when a window closes while a drag is in progress.
      for _ in 0..<12 {
        let next = try await read()
        let animation: Animation? =
          animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
          ? .smooth(duration: 0.2, extraBounce: 0) : nil
        withAnimation(animation) { snapshot = next }
        guard let columns = next.columns(containing: source),
          let from = columns.firstIndex(where: { $0.contains(source) }),
          let to = columns.firstIndex(where: { $0.contains(target) })
        else { return }
        let sourceRange = next.movementRange(containing: source) ?? from..<from + 1
        let targetRange = next.movementRange(containing: target) ?? to..<to + 1
        if after
          ? sourceRange.lowerBound == targetRange.upperBound
          : sourceRange.upperBound == targetRange.lowerBound
        {
          selection = source
          error = nil
          return
        }
        try await Task.sleep(for: .milliseconds(50))
      }
      error = "The layout changed. Try moving the tile again."
    } catch { self.error = "The tile could not be moved. The window list will refresh." }
  }

  func canPair(_ id: Int32, right: Bool) -> Bool {
    guard !busy, let columns = snapshot?.columns(containing: id),
      let index = columns.firstIndex(where: { $0.contains(id) }), columns[index].pairID == nil
    else { return false }
    let neighbor = index + (right ? 1 : -1)
    return columns.indices.contains(neighbor) && columns[neighbor].pairID == nil
  }

  func pairing(_ id: Int32, command: String, argument: String? = nil) {
    guard !busy, session.phase == .running else { return }
    Task {
      busy = true
      defer { busy = false }
      do {
        let before = snapshot?.displays.flatMap(\.columns).first { $0.contains(id) }?.pairID
        let result = try await runner.run(
          session.engineURL,
          arguments: ["send-cmd", "window", command, String(id)] + (argument.map { [$0] } ?? []),
          environment: session.engineEnvironment, timeout: 2)
        guard result.status == 0 else { throw SessionError.commandFailed }
        for _ in 0..<12 {
          try await Task.sleep(for: .milliseconds(50))
          let next = try await read()
          snapshot = next
          let pair = next.displays.flatMap(\.columns).first { $0.contains(id) }?.pairID
          if command == "pairfitid"
            || (command == "unpairid" ? pair == nil : pair != nil && pair != before)
          {
            selection = id
            error = nil
            return
          }
        }
        error = "The neighboring tiles changed. Try pairing them again."
      } catch { self.error = "The window list could not be updated." }
    }
  }

  private func handleKey(_ event: NSEvent) -> Bool {
    switch event.keyCode {
    case 53: hide()
    case 36, 76: if let selection { focus(selection) }
    case 123, 124, 48:
      let step =
        event.keyCode == 123 || event.keyCode == 48 && event.modifierFlags.contains(.shift) ? -1 : 1
      let columns = snapshot?.displays.flatMap(\.columns) ?? []
      guard !columns.isEmpty else { return true }
      let index = columns.firstIndex { $0.contains(selection ?? 0) } ?? 0
      let next = (index + step + columns.count) % columns.count
      if event.keyCode != 48, event.modifierFlags.contains(.shift), let selection {
        guard let local = snapshot?.columns(containing: selection),
          let range = snapshot?.movementRange(containing: selection)
        else { return true }
        let destination = step > 0 ? range.upperBound : range.lowerBound - 1
        guard local.indices.contains(destination) else { return true }
        let target = local[destination].id
        Task { await move(selection, beside: target, after: step > 0) }
      } else {
        selection = columns[next].id
      }
    default: return false
    }
    return true
  }
}

@MainActor
private final class OverviewHostingView: NSHostingView<OverviewView> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class OverviewPanel: NSPanel {
  var onKey: ((NSEvent) -> Bool)?
  var onResign: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  override func keyDown(with event: NSEvent) {
    if onKey?(event) != true { super.keyDown(with: event) }
  }
  override func resignKey() {
    super.resignKey()
    onResign?()
  }
}
