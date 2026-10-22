import AppKit
import ApplicationServices
import RibbonCore

@_silgen_name("_AXUIElementGetWindow")
private func axWindowID(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>)
  -> AXError

struct ApplicationIdentity: Sendable {
  let pid: Int32
  let bundleID: String
  let launchTime: Double

  @MainActor
  static var runningBundleIDs: Set<String> {
    Set(
      NSWorkspace.shared.runningApplications.compactMap {
        $0.activationPolicy == .regular ? $0.bundleIdentifier : nil
      })
  }

  @MainActor
  static func running(in bundles: Set<String>) -> [Self] {
    NSWorkspace.shared.runningApplications.compactMap { app in
      guard let bundle = app.bundleIdentifier, bundles.contains(bundle), let launch = app.launchDate
      else { return nil }
      return Self(
        pid: app.processIdentifier, bundleID: bundle, launchTime: launch.timeIntervalSince1970)
    }
  }
}

struct RecoveryResult: Sendable {
  let restored: Int
  let failed: Int
}

enum AccessibilityWorkspace {
  static func snapshot(
    _ applications: [ApplicationIdentity], strict: Bool = true
  ) async throws -> [SavedWindow] {
    try await Task.detached(priority: .userInitiated) {
      try applications.flatMap { app -> [SavedWindow] in
        guard let current = windows(for: app.pid) else {
          if strict { throw WorkspaceError.unreadableApplication }
          return []
        }
        return current.compactMap { window -> SavedWindow? in
          guard restorable(window) else { return nil }
          guard let frame = frame(of: window), frame.width > 0, frame.height > 0 else { return nil }
          var id: CGWindowID = 0
          guard axWindowID(window, &id) == .success, id != 0 else { return nil }
          return SavedWindow(
            pid: app.pid, bundleID: app.bundleID, launchTime: app.launchTime,
            windowID: id, frame: WindowFrame(frame))
        }
      }
    }.value
  }

  static func restore(
    _ journal: RecoveryJournal, applications: [ApplicationIdentity],
    displays: [CGRect]
  ) async -> RecoveryResult {
    await Task.detached(priority: .userInitiated) {
      var restored = 0
      var failed = 0
      for app in applications {
        let records = journal.windows.filter {
          $0.belongs(toPID: app.pid, bundle: app.bundleID, launchedAt: app.launchTime)
        }
        guard let current = windows(for: app.pid) else {
          failed += records.count
          continue
        }
        for window in current where restorable(window) {
          var id: CGWindowID = 0
          guard axWindowID(window, &id) == .success, let currentFrame = frame(of: window) else {
            failed += 1
            continue
          }
          let record = records.first { $0.windowID == id }
          // New windows have no pre-session placement: recover visibility, without
          // assigning a prior process's saved geometry to a reused window ID.
          let target = fitted(record?.frame.rect ?? currentFrame, to: displays)
          if approximatelyEqual(currentFrame, target) {
            restored += 1
            continue
          }
          _ = set(window, attribute: kAXSizeAttribute, size: target.size)
          _ = set(window, attribute: kAXPositionAttribute, point: target.origin)
          _ = set(window, attribute: kAXSizeAttribute, size: target.size)
          if let actual = frame(of: window), approximatelyEqual(actual, target) {
            restored += 1
          } else {
            failed += 1
          }
        }
      }
      return RecoveryResult(restored: restored, failed: failed)
    }.value
  }

  private static func restorable(_ window: AXUIElement) -> Bool {
    var role: CFTypeRef?
    var minimized: CFTypeRef?
    var fullscreen: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &role) == .success,
      [kAXStandardWindowSubrole, kAXFloatingWindowSubrole].contains(role as? String ?? "")
    else { return false }
    _ = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
    _ = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreen)
    return (minimized as? Bool) != true && (fullscreen as? Bool) != true
  }

  private static func windows(for pid: Int32) -> [AXUIElement]? {
    let application = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(application, 0.25)
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        == .success,
      let windows = value as? [AXUIElement]
    else { return nil }
    for window in windows { AXUIElementSetMessagingTimeout(window, 0.25) }
    return windows
  }

  private static func frame(of window: AXUIElement) -> CGRect? {
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)
        == .success,
      AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
      let positionValue, let sizeValue,
      CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &point),
      AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size)
    else { return nil }
    return CGRect(origin: point, size: size)
  }

  private static func set(
    _ window: AXUIElement, attribute: String, point: CGPoint? = nil, size: CGSize? = nil
  ) -> Bool {
    let value: AXValue?
    if var point {
      value = AXValueCreate(.cgPoint, &point)
    } else if var size {
      value = AXValueCreate(.cgSize, &size)
    } else {
      return false
    }
    guard let value else { return false }
    return AXUIElementSetAttributeValue(window, attribute as CFString, value) == .success
  }

  private static func fitted(_ original: CGRect, to displays: [CGRect]) -> CGRect {
    guard
      let display = displays.first(where: {
        $0.contains(CGPoint(x: original.midX, y: original.midY))
      }) ?? displays.first
    else { return original }
    let size = CGSize(
      width: min(original.width, display.width), height: min(original.height, display.height))
    return CGRect(
      x: min(max(original.minX, display.minX), display.maxX - size.width),
      y: min(max(original.minY, display.minY), display.maxY - size.height),
      width: size.width, height: size.height)
  }

  private static func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 3 && abs(a.minY - b.minY) < 3
      && abs(a.width - b.width) < 3 && abs(a.height - b.height) < 3
  }
}

private enum WorkspaceError: Error, LocalizedError {
  case unreadableApplication
  var errorDescription: String? {
    "A selected application did not provide its window list. No layout changes were started."
  }
}
