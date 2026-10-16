"""Run reusable constrained interaction scenarios against the real Godot components."""

import argparse
from pathlib import Path
import socket
import subprocess

from actor import Actor, Report
from body import load_profiles
from client import Client, launch

PROMPT_FAULTS = (("rising", ("reach", "view_angle")), ("far", ("reach",)),
                 ("tiny", ("angular_size",)), ("occluded", ("occluded",)),
                 ("head_anchored", ("occluded",)))

def arrange(client, profile, limits, report, side="right", item="chair", fault="", yaw=0, origin=(0, 0, 0)):
    """Fixture arrangement only. Grabs and storage must still use controller input."""
    client.send("fixture", eye_height=profile.eye_height, item=item, side=side,
                fault=fault, yaw=yaw, origin=origin)
    actor = Actor(client, profile, limits, report)
    actor.look(pitch=-30, yaw=15 if side == "left" else -15)
    return actor


def furniture_storage(actor, side, item, yaw, image_name=None):
    other = "left" if side == "right" else "right"
    actor.grab(item, side)
    actor.watch("put_away", other, stable=True)
    height = actor.body.profile.eye_height
    x = -0.26 if side == "left" else 0.26
    for y in (height - 0.17, height - 0.46, height - 0.35):
        actor.move(side, actor.body.local_point((x, y, -0.30)))
    actor.rotate(side, [0, yaw + (10 if side == "right" else -10), 0])
    actor.look(pitch=-15, yaw=15)
    actor.look(pitch=-25, yaw=-15)
    actor.look(pitch=-20)
    if image_name:
        actor.capture(image_name)
    actor.touch("put_away", other)
    actor.expect(lambda state: state["inventory"].get(item) == 1
                 and not state["hands"][side]["held"], "furniture returned through physical contact")


def run_cases(client, profiles, limits, report, images=False):
    report.expected_count = len(profiles) * 4 + len(PROMPT_FAULTS) + 6
    for index, profile in enumerate(profiles):
        yaw = (0, 45, 135)[index % 3]
        origin = (index * 2, 0, -index)
        for side in ("left", "right"):
            for item in ("chair", "lamp"):
                name = f"{profile.name}/{side}/{item}"
                with report.case(name):
                    actor = arrange(client, profile, limits, report, side, item, yaw=yaw, origin=origin)
                    furniture_storage(actor, side, item, yaw, name.replace("/", "-") if images else None)

    profile = profiles[0]
    for fault, codes in PROMPT_FAULTS:
        with report.case("reject/" + fault, codes):
            actor = arrange(client, profile, limits, report, item="lamp", fault=fault)
            actor.grab("lamp", "right")
            actor.watch("put_away", "left")

    with report.case("reject/chasing-prompt", ("target_moved",)):
        actor = arrange(client, profile, limits, report, fault="chasing")
        actor.grab("chair", "right")
        actor.watch("put_away", "left", stable=True)
        actor.move("right", actor.body.local_point((0.26, profile.eye_height - 0.20, -0.30)))

    with report.case("reject/holding-hand", ("wrong_hand",)):
        actor = arrange(client, profile, limits, report)
        actor.grab("chair", "right")
        actor.touch("put_away", "right")

    with report.case("reject/path-through-obstacle", ("path_blocked",)):
        actor = arrange(client, profile, limits, report, fault="path_blocked")
        actor.move("left", actor.body.local_point((-0.26, profile.eye_height - 0.35, -0.35)))

    with report.case("reject/path-through-torso", ("torso",)):
        actor = arrange(client, profile, limits, report)
        actor.move("right", actor.body.local_point((0, profile.eye_height - 0.40, 0.04)))

    with report.case("reject/excessive-head-turn", ("head_yaw",)):
        actor = arrange(client, profile, limits, report)
        actor.look(yaw=limits.max_head_yaw + 1)

    with report.case("reject/implicit-body-turn", ("body_moved", "body_turned")):
        actor = arrange(client, profile, limits, report)
        client.send("look", rotation=[0, 30, 0]) # deliberate misuse of the old functional helper
        actor.move("right", actor.observe()["pose"]["hands"]["right"]["position"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--out", default="build/playtest-body")
    parser.add_argument("--profiles", type=Path, default=Path(__file__).with_name("body_profiles.json"))
    parser.add_argument("--rendered", action="store_true", help="Render synthetic eye-view PNGs without a headset")
    args = parser.parse_args()
    profiles, limits, assumptions = load_profiles(args.profiles)
    if not args.port:
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            args.port = sock.getsockname()[1]
    args.headless = not args.rendered
    args.fixture = "interaction"
    args.profile = "playtest_body_rendered" if args.rendered else "playtest_body"
    args.godot = None
    process = launch(args)
    client = Client(args.port)
    report = Report(args.out, assumptions)
    try:
        run_cases(client, profiles, limits, report, args.rendered)
    finally:
        if process.poll() is None:
            try:
                client.send("quit")
                process.wait(timeout=5)
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                process.terminate()
                process.wait(timeout=5)
        if process.returncode:
            print(f"Godot exited with code {process.returncode}; inspect {Path(args.out) / 'godot.log'}", flush=True)
            report.cases.append({"name": "engine_session", "passed": False,
                                 "error": f"Godot exit code {process.returncode}"})
        passed = report.save()
        report.close()
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
