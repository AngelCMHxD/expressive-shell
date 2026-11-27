#!/usr/bin/env python3
"""Manage swayidle according to ~/.config/expressive-shell/settings.json."""

import json
import shutil
import subprocess
import sys
from pathlib import Path

SETTINGS_PATH = Path.home() / ".config" / "expressive-shell" / "settings.json"


def main():
    # Stop any existing swayidle managed by this user
    subprocess.run(["pkill", "-x", "swayidle"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    if not shutil.which("swayidle"):
        return

    enabled = True
    lock_sec = 300
    sleep_sec = 900

    if SETTINGS_PATH.exists():
        try:
            data = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
            if isinstance(data.get("idleEnabled"), bool):
                enabled = data["idleEnabled"]
            if isinstance(data.get("idleLockSec"), (int, float)):
                lock_sec = max(0, int(data["idleLockSec"]))
            if isinstance(data.get("idleSleepSec"), (int, float)):
                sleep_sec = max(0, int(data["idleSleepSec"]))
        except Exception:
            pass

    if not enabled:
        return

    cmd = ["swayidle", "-w", "before-sleep", "qs ipc call shell lock"]
    if lock_sec > 0:
        cmd += ["timeout", str(lock_sec), "qs ipc call shell lock"]
    if sleep_sec > 0:
        cmd += ["timeout", str(sleep_sec), "systemctl suspend"]

    # Spawn detached via umbriel if available, else direct start_new_session
    if shutil.which("umbriel"):
        subprocess.Popen(["umbriel", "msg", "spawn", *cmd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    else:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


if __name__ == "__main__":
    main()
