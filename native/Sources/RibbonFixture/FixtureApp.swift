import AppKit
import RibbonCore
import SwiftUI

@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate {
  private var windows: [NSWindow] = []
  private var timer: Timer?
  private var observer: NSObjectProtocol?
  private var focusObserver: NSObjectProtocol?
  private var resizeObserver: NSObjectProtocol?
  private var motionObserver: NSObjectProtocol?
  private var motionTimer: Timer?
  private var motionSamples: [[String: Any]] = []
  private var recordingMotion = false
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
    resizeObserver = DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name("dev.ribbon.fixture.resize-window"), object: nil, queue: .main
    ) { [weak self] notification in
      let id = notification.userInfo?["id"] as? Int
      let width = notification.userInfo?["width"] as? Double
      Task { @MainActor in
        guard let self, !self.sentinel, let width, (260...2000).contains(width),
          let window = self.windows.first(where: { $0.windowNumber == id })
        else { return }
        var frame = window.frame
        frame.size.width = width
        window.setFrame(frame, display: true)
        self.writeReport()
      }
    }
    if reportURL != nil && !sentinel {
      motionObserver = DistributedNotificationCenter.default().addObserver(
        forName: NSNotification.Name("dev.ribbon.fixture.motion"), object: nil, queue: .main
      ) { [weak self] notification in
        let action = notification.object as? String
        Task { @MainActor in
          guard let self else { return }
          if action == "begin" {
            self.motionSamples = []
            self.recordingMotion = true
          } else if action == "end" {
            self.recordingMotion = false
            guard
              let url = self.reportURL?.deletingLastPathComponent()
                .appendingPathComponent("motion-frames.json"),
              let data = try? JSONSerialization.data(withJSONObject: self.motionSamples)
            else { return }
            try? data.write(to: url, options: .atomic)
          }
        }
      }
      motionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) {
        [weak self] _ in
        Task { @MainActor in
          guard let self, self.recordingMotion, self.motionSamples.count < 1200 else { return }
          self.motionSamples.append([
            "time": ProcessInfo.processInfo.systemUptime, "frames": self.windowFrames(),
          ])
        }
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
    let requestedDisplay: UInt32? = {
      guard let index = CommandLine.arguments.firstIndex(of: "--display"),
        CommandLine.arguments.indices.contains(index + 1)
      else { return nil }
      return UInt32(CommandLine.arguments[index + 1])
    }()
    let requestedIndex = screens.firstIndex { screen in
      (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        == requestedDisplay
    }
    let screenIndex =
      requestedIndex ?? (dualDisplays ? min((number - 1) / 4, screens.count - 1) : 0)
    let bounds = screens[screenIndex].visibleFrame
    let offset = dualDisplays ? (number - 1) % 4 : number - 1
    let oversizedMinimum =
      !sentinel && offset == 0 && CommandLine.arguments.contains("--oversized-minimums")
    let initialContent = NSRect(
      x: bounds.minX + 100 + Double(offset * 55),
      y: bounds.minY + 160 + Double(offset * 35),
      width: oversizedMinimum ? bounds.width + 200 : 560, height: 420)
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
      rootView: FixtureView(number: number, name: name, sentinel: sentinel)
        .frame(
          minWidth: oversizedMinimum ? bounds.width + 200 : nil,
          minHeight: oversizedMinimum ? 180 : nil))
    host.sizingOptions = oversizedMinimum ? [.minSize] : []
    window.contentView = host
    // Derive the oversized minimum from the hosting view. With empty sizing
    // options its deferred layout would clear a manually assigned minimum.
    window.setFrame(
      NSWindow.frameRect(forContentRect: initialContent, styleMask: window.styleMask), display: true
    )
    if !sentinel && CommandLine.arguments.contains("--maximized-startup") {
      window.setFrame(bounds, display: true)
    }
    window.makeKeyAndOrderFront(nil)
    windows.append(window)
    writeReport()
  }

  private func writeReport() {
    guard let reportURL else { return }
    guard
      let encoded = try? JSONSerialization.data(
        withJSONObject: windowFrames(), options: [.sortedKeys])
    else { return }
    try? encoded.write(to: reportURL, options: .atomic)
  }

  private func windowFrames() -> [[String: Any]] {
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    return windows.filter(\.isVisible).map { window in
      [
        "id": window.windowNumber, "x": window.frame.minX, "y": top - window.frame.maxY,
        "width": window.frame.width, "height": window.frame.height, "focused": window.isKeyWindow,
        "main": window.isMainWindow, "keyEligible": window.canBecomeKey,
        "appActive": NSApp.isActive,
        "minimumWidth": window.minSize.width,
        "screenID":
          (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
          .uint32Value ?? 0,
      ]
    }
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
          : "A real, disposable Mac window.\nUse your Ribbon shortcuts to navigate."
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
