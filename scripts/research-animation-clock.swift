// Windowless timing experiment. Never activates an app, creates a window,
// queries Accessibility, captures a screen, or sends system input.
import AppKit
import QuartzCore

func stats(_ values: [Double]) -> [String: Double] {
    let sorted = values.sorted()
    func p(_ q: Double) -> Double {
        sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(ceil(q * Double(sorted.count))) - 1)]
    }
    return ["count": Double(values.count), "p50_ms": p(0.5) * 1000,
            "p95_ms": p(0.95) * 1000, "p99_ms": p(0.99) * 1000,
            "max_ms": (sorted.last ?? 0) * 1000]
}

@MainActor
func pump(_ wait: Double) -> [NSEvent] {
    var events: [NSEvent] = []
    var deadline = Date(timeIntervalSinceNow: max(0, wait))
    while let event = NSApp.nextEvent(matching: .any, until: deadline,
                                     inMode: .default, dequeue: true) {
        deadline = .distantPast
        events.append(event)
        if event.type != .applicationDefined { NSApp.sendEvent(event) }
    }
    return events
}

func work(_ seconds: Double) {
    let end = CACurrentMediaTime() + seconds
    while CACurrentMediaTime() < end { _ = sqrt(end) }
}

@MainActor
final class LinkProbe: NSObject {
    var calls: [[String: Double]] = []
    let wake: Bool
    init(wake: Bool) { self.wake = wake }
    @objc func frame(_ link: CADisplayLink) {
        calls.append(["callback": CACurrentMediaTime(), "timestamp": link.timestamp,
                      "target": link.targetTimestamp, "duration": link.duration])
        if wake, let event = NSEvent.otherEvent(with: .applicationDefined,
            location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, subtype: 100, data1: 0, data2: 0) {
            NSApp.postEvent(event, atStart: false)
        }
    }
}

@main
struct ClockExperiment {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Usage: animation-clock FRESH-OUTPUT.json")
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        guard !FileManager.default.fileExists(atPath: output.path) else {
            fatalError("Refusing to overwrite an existing receipt")
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.finishLaunching()
        var trials: [[String: Any]] = []
        // Alternating orders reduce warmup/order bias. Synthetic work models
        // engine work; it does not measure AX or foreign application rendering.
        for repeatIndex in 0..<3 {
            for workMS in [0.0, 2.0, 6.0] {
                let modes = repeatIndex % 2 == 0
                    ? ["current", "deadline120", "deadline60"]
                    : ["deadline60", "deadline120", "current"]
                for mode in modes {
                    var timeout = 2 // Current recurrence after an incoming event.
                    let period = mode == "deadline60" ? 1.0 / 60 : 1.0 / 120
                    var previous = CACurrentMediaTime()
                    var due = previous + period
                    var rows: [[String: Double]] = []
                    let end = previous + 1.2
                    while CACurrentMediaTime() < end {
                        let begin = CACurrentMediaTime()
                        let wait = mode == "current" ? Double(timeout) / 1000 : max(0, due - begin)
                        let events = pump(wait)
                        let now = CACurrentMediaTime()
                        rows.append(["time": now, "interval": now - previous, "requested_wait": wait])
                        previous = now
                        // Exactly the active, drained branch in systems.rs.
                        if mode == "current" {
                            if !events.isEmpty { timeout = 1 }
                            timeout = min(timeout, 16) + 1
                        } else {
                            repeat { due += period } while due <= now
                        }
                        work(workMS / 1000)
                    }
                    let steady = Array(rows.dropFirst(20))
                    trials.append(["mode": mode, "repeat": repeatIndex, "work_ms": workMS,
                        "summary": stats(steady.map { $0["interval"]! }), "rows": rows])
                }
            }
        }
        var screens: [[String: Any]] = []
        for screen in NSScreen.screens {
            var observations: [[String: Any]] = []
            for wake in [false, true] {
                let target = LinkProbe(wake: wake)
                let link = screen.displayLink(target: target, selector: #selector(LinkProbe.frame(_:)))
                let hz = Float(screen.maximumFramesPerSecond)
                link.preferredFrameRateRange = CAFrameRateRange(minimum: hz, maximum: hz, preferred: hz)
                link.add(to: .main, forMode: .default)
                let start = CACurrentMediaTime()
                var returns: [Double] = []
                while CACurrentMediaTime() - start < 1.1 {
                    _ = pump(0.1)
                    returns.append(CACurrentMediaTime())
                }
                link.invalidate()
                let intervals = zip(target.calls.dropFirst(), target.calls).map {
                    $0["callback"]! - $1["callback"]!
                }
                observations.append(["posts_own_wake_event": wake,
                    "callback_summary": stats(Array(intervals.dropFirst(5))),
                    "pump_returns": returns.count, "callbacks": target.calls])
            }
            screens.append(["display_id": screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? 0,
                "width": screen.frame.width, "height": screen.frame.height,
                "scale": screen.backingScaleFactor, "maximum_fps": screen.maximumFramesPerSecond,
                "minimum_interval": screen.minimumRefreshInterval,
                "maximum_interval": screen.maximumRefreshInterval, "observations": observations])
        }
        let report: [String: Any] = ["version": 1, "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "note": "Windowless Cocoa waits and display-link callbacks, not compositor delivery or native app cost.",
            "trials": trials, "screens": screens]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        print("Wrote \(output.path); no desktop windows or engine sessions were changed.")
    }
}
