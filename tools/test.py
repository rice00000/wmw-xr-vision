"""Runs the whole automated suite headlessly. Exit code 0 = every check passed.
Uses its own profile, so it never touches real progress."""

import subprocess
import sys

import godot

sys.exit(subprocess.call([str(godot.executable(console=True)), "--headless", "--xr-mode", "off",
                          "--path", str(godot.ROOT), "res://tests/smoke_test.tscn", "--",
                          "--profile=smoke_test"]))
