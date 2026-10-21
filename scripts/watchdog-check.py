#!/usr/bin/env python3
"""Check that an isolated, windowless helper exits when its owning app exits."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time

app = pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="ribbon-watchdog-") as temporary:
    directory = pathlib.Path(temporary)
    config = directory / "engine.toml"
    config.write_text("[options]\nfocus_follows_mouse = false\nmouse_follows_focus = false\n[bindings]\n")
    environment = dict(os.environ, PANERU_CONFIG=str(config),
                       XDG_CONFIG_HOME=str(directory / "config"), XDG_STATE_HOME=str(directory / "state"))
    probe = subprocess.run([str(app / "Contents/MacOS/Ribbon"), "--watchdog-probe"],
                           env=environment, text=True, capture_output=True, timeout=5)
    if probe.returncode == 77:
        print(json.dumps({"status": "blocked", "reason": "Accessibility access required"}))
        sys.exit(77)
    probe.check_returncode()
    pid = int(probe.stdout.strip())
    started = time.monotonic()
    while time.monotonic() - started < 5:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            print(json.dumps({"status": "passed", "child_pid": pid, "exit_observed_ms": round((time.monotonic() - started) * 1000)}))
            sys.exit(0)
        time.sleep(0.05)
    raise SystemExit(f"Owned helper {pid} did not exit after its parent.")
