import AppKit
import CoreGraphics

NSApplication.shared.setActivationPolicy(.prohibited)

let args = CommandLine.arguments
let center = DistributedNotificationCenter.default()
switch args[1] {
case "key":
  let key = CGKeyCode(args[2])!
  print(ProcessInfo.processInfo.systemUptime)
  for down in [true, false] {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
    event?.flags = CGEventFlags(
      rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | 0x21)
    event?.post(tap: .cghidEventTap)
  }
case "focus":
  center.postNotificationName(
    NSNotification.Name("dev.ribbon.fixture.focus-window"), object: nil,
    userInfo: ["id": Int(args[2])!], deliverImmediately: true)
case "motion":
  center.postNotificationName(
    NSNotification.Name("dev.ribbon.fixture.motion"), object: args[2], deliverImmediately: true)
case "width":
  center.postNotificationName(
    NSNotification.Name("dev.ribbon.fixture.resize-window"), object: nil,
    userInfo: ["id": Int(args[2])!, "width": Double(args[3])!], deliverImmediately: true)
case "displays":
  let top = NSScreen.screens.first!.frame.maxY
  let records = NSScreen.screens.map { s in
    [
      "id": (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber)
        .doubleValue, "x": s.visibleFrame.minX, "y": top - s.visibleFrame.maxY,
      "width": s.visibleFrame.width, "height": s.visibleFrame.height,
      "maximumHz": Double(s.maximumFramesPerSecond),
    ]
  }
  print(String(data: try! JSONSerialization.data(withJSONObject: records), encoding: .utf8)!)
default: fatalError("unknown operation")
}
