#!/usr/bin/env python3
"""Choose a cozy wallpaper for each connected output; safe to call repeatedly."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")


def arguments(monitors):
    args = ["swaybg"]
    for monitor in monitors:
        width, height = monitor["width"], monitor["height"]
        if monitor.get("transform", 0) % 2:
            width, height = height, width
        orientation = "portrait" if height > width else "landscape"
        picture = CONFIG / "backgrounds" / f"dark-cozy-{orientation}.png"
        if not picture.is_file():
            raise FileNotFoundError(picture)
        args += ["-o", monitor["name"], "-i", str(picture), "-m", "fill"]
    return args


def process_token(pid):
    try:
        # Include process start time, so a recycled PID is never terminated.
        return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[19]
    except FileNotFoundError:
        return None


def main():
    if not shutil.which("swaybg"):
        return
    runtime = Path(os.environ["XDG_RUNTIME_DIR"]) / "hypr" / os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    state_file = runtime / "cozy-wallpaper.json"
    with (runtime / "cozy-wallpaper.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        monitors = json.loads(subprocess.check_output(["hyprctl", "-j", "monitors"]))
        if not monitors:
            return
        args = arguments(monitors)
        try:
            old = json.loads(state_file.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            old = {}
        alive = old.get("token") is not None and process_token(old.get("pid")) == old["token"]
        signature = [(m["name"], m["width"], m["height"], m["transform"], m["scale"]) for m in monitors]
        signature = json.loads(json.dumps(signature))
        if alive and old.get("args") == args and old.get("monitors") == signature:
            return
        child = subprocess.Popen(args, start_new_session=True, stdout=subprocess.DEVNULL)
        time.sleep(0.3)
        if child.poll() is not None:
            raise RuntimeError("swaybg failed; keeping previous wallpaper")
        state_file.write_text(json.dumps({"pid": child.pid, "token": process_token(child.pid),
                                         "args": args, "monitors": signature}))
        if alive:
            try:
                os.kill(old["pid"], signal.SIGTERM)
            except ProcessLookupError:
                pass


if __name__ == "__main__":
    main()
