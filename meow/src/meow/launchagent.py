"""macOS LaunchAgent management for the meow daemon."""

from __future__ import annotations

import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

PLIST_LABEL = "com.wandermyz.meow"
PLIST_PATH = Path.home() / "Library" / "LaunchAgents" / f"{PLIST_LABEL}.plist"

LOG_DIR = Path.home() / ".yuki-conductor" / "workspace" / "logs"
STDOUT_LOG = LOG_DIR / "meow.out.log"
STDERR_LOG = LOG_DIR / "meow.err.log"


def _find_uv() -> str:
    uv = shutil.which("uv")
    if not uv:
        raise RuntimeError("uv not found on PATH")
    return uv


def _project_dir() -> Path:
    return Path(__file__).resolve().parent.parent.parent


def _generate_plist() -> bytes:
    home = Path.home()
    path_value = ":".join([
        str(home / ".local" / "bin"),
        str(home / ".cargo" / "bin"),
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ])
    plist = {
        "Label": PLIST_LABEL,
        "ProgramArguments": [
            _find_uv(),
            "run",
            "--project",
            str(_project_dir()),
            "meow",
            "run",
        ],
        "KeepAlive": True,
        "RunAtLoad": True,
        "WorkingDirectory": str(_project_dir()),
        "EnvironmentVariables": {"PATH": path_value},
        "StandardOutPath": str(STDOUT_LOG),
        "StandardErrorPath": str(STDERR_LOG),
    }
    return plistlib.dumps(plist)


def install() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    PLIST_PATH.parent.mkdir(parents=True, exist_ok=True)
    PLIST_PATH.write_bytes(_generate_plist())
    subprocess.run(["launchctl", "load", str(PLIST_PATH)], check=True)
    print(f"Installed and loaded {PLIST_LABEL}")
    print(f"Plist:  {PLIST_PATH}")
    print(f"Stdout: {STDOUT_LOG}")
    print(f"Stderr: {STDERR_LOG}")


def uninstall() -> None:
    if PLIST_PATH.exists():
        subprocess.run(["launchctl", "unload", str(PLIST_PATH)], check=False)
        PLIST_PATH.unlink()
        print(f"Unloaded and removed {PLIST_LABEL}")
    else:
        print("LaunchAgent not installed")


def restart() -> None:
    if not PLIST_PATH.exists():
        print("LaunchAgent not installed. Run 'meow daemon install' first.")
        sys.exit(1)
    PLIST_PATH.write_bytes(_generate_plist())
    subprocess.run(["launchctl", "unload", str(PLIST_PATH)], check=False)
    subprocess.run(["launchctl", "load", str(PLIST_PATH)], check=True)
    print(f"Restarted {PLIST_LABEL}")


def status() -> None:
    result = subprocess.run(
        ["launchctl", "list"],
        capture_output=True,
        text=True,
    )
    for line in result.stdout.splitlines():
        if PLIST_LABEL in line:
            print(f"Running: {line}")
            return
    print("Not running")


def log() -> None:
    print(f"Stdout: {STDOUT_LOG}")
    print(f"Stderr: {STDERR_LOG}")
    if STDOUT_LOG.exists():
        print(f"\n--- Last 20 lines of {STDOUT_LOG.name} ---")
        for line in STDOUT_LOG.read_text().splitlines()[-20:]:
            print(line)
    if STDERR_LOG.exists() and STDERR_LOG.stat().st_size > 0:
        print(f"\n--- Last 20 lines of {STDERR_LOG.name} ---")
        for line in STDERR_LOG.read_text().splitlines()[-20:]:
            print(line)


def handle(action: str) -> None:
    actions = {
        "install": install,
        "uninstall": uninstall,
        "restart": restart,
        "status": status,
        "log": log,
    }
    actions[action]()
