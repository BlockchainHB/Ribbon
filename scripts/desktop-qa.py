#!/usr/bin/env python3
"""Run isolated native-window suites against a signed local Ribbon bundle."""
import json
import pathlib
import subprocess
import sys
import time

app = pathlib.Path(sys.argv[1]).expanduser().resolve()
output = pathlib.Path(sys.argv[2]).expanduser().resolve()
executable = app / "Contents/MacOS/Ribbon"
if not executable.is_file():
    raise SystemExit("Ribbon executable is missing")
if subprocess.run(["pgrep", "-x", "Ribbon"], capture_output=True).returncode == 0:
    raise SystemExit("Quit existing Ribbon instances before running isolated desktop QA")
if output.exists():
    raise SystemExit("Use a fresh output directory to preserve previous evidence")
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
output.mkdir(parents=True)
summary = {"status": "running", "app": str(app), "suites": {}}

try:
    for name, arguments in [("single", []), ("dual", ["--qa-dual"])]:
        directory = output / name
        directory.mkdir()
        report = directory / "report.json"
        with (directory / "process.log").open("w") as log:
            process = subprocess.Popen(
                [str(executable), *arguments, "--qa-output", str(report)],
                stdout=log, stderr=log,
            )
            try:
                deadline = time.monotonic() + 120
                while not report.exists():
                    if process.poll() is not None:
                        raise RuntimeError(f"{name}: app exited before reporting")
                    if time.monotonic() >= deadline:
                        raise RuntimeError(f"{name}: timed out; retain its recovery journal")
                    time.sleep(0.1)
                result = json.loads(report.read_text())
                summary["suites"][name] = {
                    key: result[key] for key in
                    ["status", "checks", "displays", "engineSHA256", "detail"]
                    if key in result
                }
                if result["status"] != "passed":
                    raise RuntimeError(f"{name}: {result.get('detail', result['status'])}")
                print(f"{name}: {len(result['checks'])} native checks passed", flush=True)
            finally:
                # Own test process only. Completed reports follow pause/recovery.
                # On a timeout, the helper's parent watchdog supplies cleanup.
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=3)
        time.sleep(0.5)  # Let the owned fixture applications finish terminating.
    watchdog = subprocess.run(
        [sys.executable, str(pathlib.Path(__file__).with_name("watchdog-check.py")), str(app)],
        capture_output=True, text=True, timeout=10, check=True,
    )
    summary["watchdog"] = json.loads(watchdog.stdout)
    if summary["watchdog"]["status"] != "passed":
        raise RuntimeError("Owned-helper watchdog did not pass")
    summary["status"] = "passed"
except Exception as error:
    summary["status"] = "failed"
    summary["detail"] = str(error)
    raise
finally:
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Evidence: {output / 'summary.json'}", flush=True)
