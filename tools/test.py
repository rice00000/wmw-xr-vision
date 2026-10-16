"""Runs the whole automated suite headlessly. Exit code 0 = every check passed.
Uses its own profile, so it never touches real progress."""

import subprocess
import sys

import godot

commands = [
    [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"],
    [str(godot.executable(console=True)), "--headless", "--xr-mode", "off",
     "--path", str(godot.ROOT), "res://tests/smoke_test.tscn", "--", "--profile=smoke_test"],
    [sys.executable, "tools/playtest/usability.py"],
]
for command in commands:
    result = subprocess.call(command, cwd=godot.ROOT)
    if result:
        sys.exit(result)
