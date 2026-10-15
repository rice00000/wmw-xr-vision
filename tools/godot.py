"""Finds Godot and the XR simulator runtime on each OS. Override with GODOT / XR_RUNTIME_JSON."""

import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
WINDOWS_GODOT = Path(r"D:\Program Files\Portables\Godot_v4.7.2-stable_win64.exe")
WINDOWS_RUNTIME = Path(r"C:\Program Files\MetaXRSimulator\v207.1\meta_openxr_simulator.json")


def executable(console=False):
    """The Godot binary. On Windows, console=True picks the _console build so stdout reaches us."""
    if "GODOT" in os.environ:
        return Path(os.environ["GODOT"])
    if sys.platform == "win32":
        return WINDOWS_GODOT.with_stem(WINDOWS_GODOT.stem + "_console") if console else WINDOWS_GODOT
    if sys.platform == "darwin":
        return Path("/Applications/Godot.app/Contents/MacOS/Godot")
    return Path(shutil.which("godot") or "godot")


def xr_env():
    """Environment for a windowed XR run: points OpenXR at the Meta XR Simulator when installed."""
    env = os.environ.copy()
    if "XR_RUNTIME_JSON" not in env and sys.platform == "win32" and WINDOWS_RUNTIME.exists():
        env["XR_RUNTIME_JSON"] = str(WINDOWS_RUNTIME)
    return env
