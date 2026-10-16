"""Runs the whole automated suite headlessly. Exit code 0 = every check passed.
Uses its own profile, so it never touches real progress."""

import re
import subprocess
import sys

import godot

commands = [
    [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"],
    [sys.executable, "tools/bake_speech.py", "--check"],
    [str(godot.executable(console=True)), "--headless", "--xr-mode", "off",
     "--path", str(godot.ROOT), "--editor", "--import"],
    [str(godot.executable(console=True)), "--headless", "--xr-mode", "off",
     "--path", str(godot.ROOT), "res://tests/task_lists_test.tscn", "--", "--profile=task_lists_test"],
    [str(godot.executable(console=True)), "--headless", "--xr-mode", "off",
     "--path", str(godot.ROOT), "res://tests/baked_speech_test.tscn", "--", "--profile=baked_speech_test"],
    [str(godot.executable(console=True)), "--headless", "--xr-mode", "off",
     "--path", str(godot.ROOT), "res://tests/smoke_test.tscn", "--", "--profile=smoke_test"],
    [sys.executable, "tools/playtest/usability.py"],
]
for command in commands:
    try:
        result = subprocess.run(command, cwd=godot.ROOT, capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        sys.exit("Test timed out after 300 seconds: " + " ".join(command))
    print(result.stdout, end="", flush=True)
    print(result.stderr, end="", file=sys.stderr, flush=True)
    if result.returncode:
        sys.exit(result.returncode)
    # Godot can report script errors yet exit successfully or skip a test body.
    if re.search(r"^(?:SCRIPT ERROR|ERROR):", result.stdout + result.stderr, re.MULTILINE):
        sys.exit("Engine errors during: " + " ".join(command))
