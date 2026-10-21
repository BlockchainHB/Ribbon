import AppKit
import RibbonCore
import SwiftUI

@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate {
  private var windows: [NSWindow] = []
  private var timer: Timer?
  private var observer: NSObjectProtocol?
  private var focusObserver: NSObjectProtocol?
  private var reportURL: URL?
  private var sentinel = false
  private var dualDisplays = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    sentinel = Bundle.main.bundleIdentifier == "dev.ribbon.sentinel"
    dualDisplays = CommandLine.arguments.contains("--dual-displays") && !sentinel
    if let index = CommandLine.arguments.firstIndex(of: "--report"),
      CommandLine.arguments.indices.contains(index + 1)
    {
      reportURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    }
    for _ in 0..<(sentinel ? 1 : (dualDisplays ? 8 : 4)) { addWindow() }
    observer = DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name("dev.ribbon.fixture.add-window"),
      object: nil, queue: .main
    ) { [weak self] _ in Task { @MainActor in if self?.sentinel == false { self?.addWindow() } } }
    focusObserver = DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name("dev.ribbon.fixture.focus-window"),
      object: nil, queue: .main
    ) { [weak self] notification in
      let id = notification.userInfo?["id"] as? Int
      Task { @MainActor in
        guard let self, !self.sentinel,
          let window = self.windows.first(where: { $0.windowNumber == id })
        else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.writeReport()
      }
    }
    timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.writeReport() }
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  private func addWindow() {
    let number = windows.count + 1
    let screens = NSScreen.screens
    let screenIndex = dualDisplays ? min((number - 1) / 4, screens.count - 1) : 0
    let bounds = screens[screenIndex].visibleFrame
    let offset = dualDisplays ? (number - 1) % 4 : number - 1
    let initialContent = NSRect(
      x: bounds.minX + 100 + Double(offset * 55),
      y: bounds.minY + 160 + Double(offset * 35), width: 560, height: 420)
    let window = NSWindow(
      contentRect: initialContent,
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered, defer: false, screen: screens[screenIndex])
    window.title = sentinel ? "Ribbon — excluded test window" : "Ribbon Demo \(number)"
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.minSize = NSSize(width: 260, height: 180)
    let name = ["Editor", "Browser", "Terminal", "Notes"][(number - 1) % 4]
    let host = NSHostingView(
      rootView: FixtureView(number: number, name: name, sentinel: sentinel))
    host.sizingOptions = []
    window.contentView = host
    window.setFrame(
      NSWindow.frameRect(forContentRect: initialContent, styleMask: window.styleMask), display: true
    )
    window.makeKeyAndOrderFront(nil)
    windows.append(window)
    writeReport()
  }

  private func writeReport() {
    guard let reportURL else { return }
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    let data: [[String: Any]] = windows.filter(\.isVisible).map { window in
      [
        "id": window.windowNumber, "x": window.frame.minX, "y": top - window.frame.maxY,
        "width": window.frame.width, "height": window.frame.height, "focused": window.isKeyWindow,
        "main": window.isMainWindow, "keyEligible": window.canBecomeKey,
        "appActive": NSApp.isActive,
        "screenID":
          (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
          .uint32Value ?? 0,
      ]
    }
    guard let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])
    else { return }
    try? encoded.write(to: reportURL, options: .atomic)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private struct FixtureView: View {
  let number: Int
  let name: String
  let sentinel: Bool
  private var tint: Color { sentinel ? .gray : [.teal, .blue, .orange, .purple][(number - 1) % 4] }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Image(systemName: sentinel ? "lock" : "rectangle.split.3x1").font(.title)
        Spacer()
        Text(String(format: "%02d", number)).font(
          .system(size: 56, weight: .light, design: .rounded))
      }.foregroundStyle(tint)
      Spacer()
      Text(sentinel ? "Outside the strip" : name).font(.system(size: 32, weight: .semibold))
      Text(
        sentinel
          ? "This test window must stay in its original position."
          : "A real, disposable Mac window.\nUse Control–Option + arrows to navigate."
      )
      .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      Divider()
      Text("Ribbon test window · Contains no personal data").font(.caption).foregroundStyle(
        .secondary)
    }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(tint.opacity(0.04))
  }
}

@main
@MainActor
enum FixtureEntry {
  static func main() {
    let app = NSApplication.shared
    let delegate = FixtureDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
  }
}
