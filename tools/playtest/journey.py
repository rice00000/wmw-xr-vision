"""Constrained real-island journey with deterministic misses, no hesitation delays.

Uses privileged setup only once, to reset an isolated profile and fit the avatar.
All progression afterwards comes from tracked hand poses, buttons and sticks.
"""
import argparse
import json
from pathlib import Path
import socket
import time

from actor import Actor, Report
from body import ConstraintError, add, sub, mul, distance, load_profiles, require
from client import Client, launch


def run_journey(client, profile, limits, report, images=False):
    client.send("journey_setup", eye_height=profile.eye_height)
    actor = Actor(client, profile, limits, report)
    report.expected_count = 8

    def stage(name, operation):
        with report.case(name):
            operation()
            if images:
                actor.capture(name)
        require(report.cases[-1]["passed"], "journey_stopped", stage=name)

    def state():
        return client.state()

    def target(kind):
        snapshot = actor.wait_for(lambda s: any(kind in t["path"] and t.get("target") for t in s["trials"]),
                                  "next " + kind + " target")
        return next(t["target"] for t in snapshot["trials"] if kind in t["path"] and t.get("target"))

    def open_menu():
        # Controller Menu is a genuine production entry point, including release semantics.
        actor.button("left", "menu_button", True)
        actor.button("left", "menu_button", False)
        actor.expect(lambda s: s["menu_open"], "menu opened on controller release")

    def close_menu():
        actor.click("menu_tab_home")
        actor.click("menu_close")
        actor.expect(lambda s: not s["menu_open"], "menu closed through ray click")
        actor.look()

    def route(points):
        actor.park("right")
        actor.park("left")
        for point in points:
            actor.teleport(point)

    def welcome():
        actor.wait_for(lambda s: any(o["id"] == "magic_ball" for o in s["objects"]), "welcome ball")
        ball = next(o for o in state()["objects"] if o["id"] == "magic_ball")
        actor.walk_to((ball["position"][0] - .15, actor.body.origin[1], ball["position"][2] + .35))
        ball = next(o for o in state()["objects"] if o["id"] == "magic_ball")
        actor.face(ball["position"])
        actor.look_at(ball["position"])
        actor.grab("magic_ball", "right", consumed=True)
        actor.expect(lambda s: s["waiting_for"] == "opened:menu", "welcome grab advanced")
        actor.release("right")
        actor.park("right")

    def menu_miss():
        star = actor.observe(["star"])["targets"]["star"]
        actor.look_at(star["point"])
        actor.wrist_menu(miss=True)
        actor.wrist_menu()
        actor.park("right")
        before = state()["menu_page"]
        actor.click("menu_tab_shop", miss=True)
        actor.expect(lambda s: s["menu_page"] == before, "miss did not change menu page")
        actor.click("menu_tab_shop")
        actor.expect(lambda s: s["menu_page"] == "shop", "corrected ray opened Shop")
        close_menu()

    def picnic_arrival():
        route([(0, 0, 23), (0, 0, 17), (0, 0, 11), (4, 0, 7), (9.5, 0, 2.80)])
        actor.face((9.5, 1, 2))
        actor.expect(lambda s: s["task"] == "find_it", "picnic entered through tracked locomotion")

    def search():
        for index in range(5):
            obj = target("PicnicStation")
            for offset in (0, -.18, .18, -.32, .32):
                actor.walk_to((9.5 + offset, actor.body.origin[1], 2.8))
                actor.look_at(obj["position"])
                side = "right" if obj["position"][0] > actor.body.origin[0] else "left"
                try:
                    actor.grab(obj["path"], side, consumed=True)
                    break
                except ConstraintError as error:
                    if error.code not in ("reach", "occluded", "path_blocked", "hands_overlap"):
                        raise
                    report.record("search_approach_rejected", offset=offset, code=error.code, evidence=error.evidence)
            else:
                require(False, "no_feasible_grasp", target=obj["path"])
            actor.expect(lambda s: not s["hands"][side]["held"], "correct target released by game")
            actor.release(side)
            # The selected object lifts through its former contact while the hand retreats.
            actor.park(side, contact=obj["path"])
            report.record("search_round", round=index + 1, target=obj["path"])
        actor.wait_for(lambda s: s["task"] == "butterflies", "five search rounds rewarded")

    def meadow_arrival():
        route([(5, 0, 3), (0, 0, 0), (-5, 0, -4), (-8, 0, -8)])
        actor.face((-8, 1, -10))
        actor.expect(lambda s: s["task"] == "butterflies", "meadow entered")

    def catch():
        for index in range(5):
            obj = target("MeadowStation")
            actor.look_at(obj["position"])
            if index == 0:
                # Stop short of contact. The same observation and path constraints apply.
                actor.miss_touch(obj["path"], "right")
                actor.expect(lambda s: any(t.get("target", {}).get("path") == obj["path"]
                                          for t in s["trials"]), "missed touch left butterfly active")
            before = state()["event_sequence"]
            for attempt in range(8):
                current = actor.observe([obj["path"]])["targets"][obj["path"]]
                if current is None or current.get("done"):
                    break
                actor.look_at(current["point"])
                actor.touch(obj["path"], "right")
                actor.watches.clear()
            actor.expect(lambda s: any(e["sequence"] > before and e["kind"] == "trial"
                                      and e["data"]["data"].get("result") == "caught"
                                      for e in s["recent"]), "corrected physical contact caught butterfly")
            actor.park("right")
        actor.wait_for(lambda s: s["task"] == "first_furniture", "five catches rewarded")

    def purchase_and_home():
        open_menu()
        actor.click("menu_tab_shop")
        actor.click("menu_buy_chair")
        actor.expect(lambda s: s["inventory"].get("chair") == 1, "chair purchased")
        actor.click("menu_tab_bag")
        actor.expect(lambda s: any(b["id"] == "menu_take_out_chair" for b in s["buttons"]), "chair in bag")
        close_menu()
        route([(-8, 0, -2), (-5, 0, 3), (-5, 0, 8), (-9, 0, 8), (-9, .12, 4)])
        actor.face((-9, 1, 2))

    def furniture():
        open_menu()
        actor.click("menu_tab_bag")
        actor.click("menu_take_out_chair")
        actor.expect(lambda s: s["hands"]["right"]["held"] == "chair", "bag handed chair to player")
        actor.move("right", actor.body.local_point((.26, profile.eye_height - .35, -.30)))
        actor.button("right", "grip_click", True)
        actor.release("right")
        actor.wait_for(lambda s: s["task"] == "", "placement completed tutorial")
        actor.look_at(actor.observe(["chair"])["targets"]["chair"]["point"])
        actor.grab("chair", "right")
        actor.look_at(actor.observe(["put_away"])["targets"]["put_away"]["point"])
        actor.watch("put_away", "left", stable=True)
        actor.miss_touch("put_away", "left")
        actor.expect(lambda s: s["hands"]["right"]["held"] == "chair" and not s["inventory"].get("chair"),
                     "storage miss did not consume furniture")
        actor.touch("put_away", "left")
        actor.expect(lambda s: s["inventory"].get("chair") == 1 and not s["hands"]["right"]["held"],
                     "corrected touch stored furniture")
        actor.release("right")
        actor.park("left")
        actor.park("right")
        open_menu()
        actor.click("menu_tab_tasks")
        actor.expect(lambda s: any("practice" in b["id"] for b in s["buttons"]), "repeatable task list unlocked")

    for name, operation in [("welcome", welcome), ("menu-aim-miss-and-recovery", menu_miss),
                            ("navigate-picnic", picnic_arrival), ("search-five-rounds", search),
                            ("navigate-meadow", meadow_arrival), ("catch-miss-and-recovery", catch),
                            ("purchase-and-navigate-home", purchase_and_home), ("placement-storage-and-repeatable", furniture)]:
        stage(name, operation)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="build/playtest-journey")
    parser.add_argument("--body", default="medium_reach")
    parser.add_argument("--rendered", action="store_true", help="Capture eye-view checkpoints without an XR runtime")
    args = parser.parse_args()
    profiles, limits, assumptions = load_profiles()
    profile = next((p for p in profiles if p.name == args.body), None)
    if profile is None:
        parser.error("Unknown body profile")
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        args.port = sock.getsockname()[1]
    args.headless, args.journey, args.godot = not args.rendered, True, None
    args.profile = "playtest_journey_" + profile.name
    process = launch(args)
    client = Client(args.port)
    report = Report(args.out, assumptions)
    started = time.monotonic()
    try:
        run_journey(client, profile, limits, report, args.rendered)
    finally:
        try:
            client.send("quit")
            process.wait(timeout=5)
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            report.engine_result(process.returncode)
            passed = report.save()
            report.close()
            print(f"Journey: {time.monotonic() - started:.2f}s", flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
