#!/usr/bin/env python3
"""Check maximized startup/reveal/recovery using disposable windows only."""
import json
from pathlib import Path
import subprocess
import sys
import time

app = Path(sys.argv[1]).expanduser().resolve()
output = Path(sys.argv[2]).expanduser().resolve()
if subprocess.run(["pgrep", "-x", "Ribbon"], capture_output=True).returncode == 0:
    raise SystemExit("Quit Ribbon before running isolated startup QA")
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
output.mkdir(parents=True, exist_ok=False)
summary = {"status": "running", "suites": {}}


def check_menu(directory):
    observations = []
    for attempt in range(3):
        click = subprocess.Popen(
            ["osascript", "-e", 'tell application "System Events" to tell process "Ribbon" '
             'to click menu bar item 1 of menu bar 2'],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        )
        try:
            prefix = 'tell application "System Events" to tell process "Ribbon" to get '
            target = " of menu 1 of menu bar item 1 of menu bar 2"
            opened = False
            time.sleep(0.15)
            for _ in range(3):
                size = subprocess.run(["osascript", "-e", prefix + "size" + target],
                                      capture_output=True, text=True, timeout=3)
                opened = size.returncode == 0 and all(
                    float(x.strip()) > 0 for x in size.stdout.split(","))
                if opened:
                    break
                time.sleep(0.05)
            names = subprocess.run(["osascript", "-e", prefix + "name of every menu item" + target],
                                   capture_output=True, text=True, timeout=3)
            observations.append({"attempt": attempt, "names": names.stdout,
                                 "size": size.stdout, "error": size.stderr})
            subprocess.run(["osascript", "-e", 'tell application "System Events" to key code 53'],
                           check=True, timeout=3)
            click.wait(timeout=3)
            if opened:
                break
        finally:
            if click.poll() is None:
                click.kill()
                click.wait()
    (directory / "menu-observation.json").write_text(json.dumps(observations, indent=2))
    result = {"opened": opened and "Arrange Windows" in names.stdout,
              "settings": "Settings…" in names.stdout, "closed": click.returncode == 0}
    (directory / "menu-check-result.json").write_text(json.dumps(result))


try:
    for name, flags in [("single", []), ("dual", ["--qa-dual"])]:
        directory = output / name
        directory.mkdir()
        report = directory / "report.json"
        with (directory / "process.log").open("w") as log:
            process = subprocess.Popen(
                [str(app / "Contents/MacOS/Ribbon"), "--qa-maximized-startup",
                 "--qa-external-input", "--qa-output", str(report), *flags],
                stdout=log, stderr=log,
            )
            try:
                time.sleep(0.5)
                subprocess.run(["open", "-a", str(app)], check=True)
                deadline = time.monotonic() + 120
                menu_checked = False
                pressed = set()
                while not report.exists():
                    if process.poll() is not None:
                        raise RuntimeError(f"{name}: Ribbon exited before reporting")
                    if time.monotonic() >= deadline:
                        raise RuntimeError(f"{name}: timed out; retain the recovery journal")
                    if (directory / "menu-check-request.json").exists() and not menu_checked:
                        check_menu(directory)
                        menu_checked = True
                    for request in directory.glob("switch-request-*.json"):
                        if request.name in pressed:
                            continue
                        action = '\n'.join([
                            'tell application "System Events"',
                            'tell process "Ribbon"',
                            'set frontmost to true',
                            'set nodes to entire contents of window "General"',
                            'repeat with node in nodes',
                            'try',
                            'if role of node is "AXCheckBox" and name of node is "Window management" then',
                            'set p to position of node',
                            'set s to size of node',
                            'return ((item 1 of p) + (item 1 of s) / 2) as text & "," & ((item 2 of p) + (item 2 of s) / 2) as text',
                            'end if', 'end try', 'end repeat',
                            'error "Enable Ribbon control missing"', 'end tell', 'end tell',
                        ])
                        result = subprocess.run(["osascript", "-e", action],
                                                capture_output=True, text=True, timeout=4)
                        (directory / (request.stem + "-result.txt")).write_text(
                            result.stdout + result.stderr)
                        if result.returncode != 0:
                            raise RuntimeError("External Ribbon switch action failed")
                        point = [float(value) for value in result.stdout.strip().split(",")]
                        if len(point) != 2:
                            raise RuntimeError("Invalid native switch target")
                        click_code = """import CoreGraphics
let p = CGPoint(x: Double(CommandLine.arguments[1])!, y: Double(CommandLine.arguments[2])!)
for type: CGEventType in [.leftMouseDown, .leftMouseUp] {
    let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
    event?.flags = []
    event?.setIntegerValueField(.mouseEventClickState, value: 1)
    event?.post(tap: .cghidEventTap)
}
"""
                        subprocess.run(["swift", "-e", click_code, *map(str, point)],
                                       check=True, timeout=4)
                        pressed.add(request.name)
                    time.sleep(0.1)
                result = json.loads(report.read_text())
                summary["suites"][name] = result
                if result["status"] != "passed":
                    raise RuntimeError(f"{name}: {result.get('detail', result['status'])}")
                print(f"{name}: {len(result['checks'])} native checks passed", flush=True)
            finally:
                # The suite restores before reporting; the watchdog covers a killed parent.
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=12)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=3)
        time.sleep(0.5)
    summary["status"] = "passed"
except Exception as error:
    summary["status"] = "failed"
    summary["detail"] = str(error)
    raise
finally:
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Evidence: {output / 'summary.json'}", flush=True)
