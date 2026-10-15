"""Drive the real hands/menu through the island and leave PNGs for visual review.

This checks interaction/progression, not human recognition, comfort or Quest performance.
State assertions catch failures; screenshots still need to be inspected by a person/agent.
"""

import argparse
import html
import json
from pathlib import Path
import time

from client import Client


def write_gallery(out):
    figures = "\n".join(f'<figure><a href="{html.escape(path.name)}"><img src="{html.escape(path.name)}" loading="lazy"></a>'
                        f'<figcaption>{html.escape(path.name)}</figcaption></figure>' for path in sorted(out.glob("*.png")))
    (out / "review.html").write_text(
        '<!doctype html><meta charset="utf-8"><title>XRVision visual review</title>'
        '<style>body{background:#151923;color:#eee;font:16px system-ui;margin:30px}'
        'main{display:grid;grid-template-columns:repeat(auto-fit,minmax(450px,1fr));gap:20px}'
        'figure{margin:0}img{width:100%}figcaption{padding:8px}</style>'
        '<h1>XRVision visual review</h1><p>Real rendered checkpoints. Inspect the pictures; '
        'script completion alone does not mean visual PASS.</p><main>' + figures + '</main>', encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18765)
    parser.add_argument("--out", default="build/playtest")
    parser.add_argument("--no-images", action="store_true", help="Headless interaction check only")
    parser.add_argument("--gallery-only", action="store_true", help="Index existing screenshots without playing")
    args = parser.parse_args()
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    if args.gallery_only:
        write_gallery(out)
        return
    client = Client(args.port)
    notes = []

    def note(text):
        print(text, flush=True)
        notes.append(text)
        (out / "observations.txt").write_text("\n".join(notes) + "\n", encoding="utf-8")

    def check(condition, message):
        if not condition:
            raise AssertionError(message)

    def capture(name, at=None, offset=None):
        if args.no_images:
            return
        if at is None:
            state = client.state()
            if state["menu_open"] and state["buttons"]:
                # Same eye position, looking down at the menu as a player would.
                centre = [sum(b["position"][i] for b in state["buttons"]) / len(state["buttons"])
                          for i in range(3)]
                client.send("view", mode="fixed", position=state["eye"], at=centre)
            else:
                client.send("view", mode="eyes")
        else:
            offset = offset or [0.8, 0.7, 1.1]
            client.send("view", mode="fixed", at=at,
                        position=[a + b for a, b in zip(at, offset)])
        result = client.send("capture", name=name)
        write_gallery(out)
        note("IMAGE " + result["path"])

    def park(side="right"):
        eye = client.state()["eye"]
        client.send("move", hand=side, position=[eye[0] + (-0.5 if side == "left" else 0.45),
                                                eye[1] - 0.35, eye[2] + 0.15],
                    rotation=[0, 0, 0], seconds=0.3)

    def click(button):
        before = client.state()["recent"]
        result = client.send("click", to=button)["state"]
        if button != "star":
            old_ms = max((entry["ms"] for entry in before), default=-1)
            check(any(entry["ms"] >= old_ms and entry["kind"] == "fact"
                      and entry["data"].get("what") == "pressed"
                      and entry["data"].get("id") == button for entry in result["recent"]),
                  "Ray click did not press " + button)
        return result

    def menu():
        park()
        if not client.state()["menu_open"]:
            client.send("poke", to="star")
        check(client.state()["menu_open"], "Star did not open menu")
        # Cross the wrist again before aiming at the panel.
        # The hidden star is an entry point, so this must leave the panel open.
        client.send("poke", to="star")
        check(client.state()["menu_open"], "Crossing the wrist closed the menu")

    def button(action, pressed):
        return client.send("button", hand="right", action=action, pressed=pressed)["state"]

    def target(trial_kind):
        state = client.until(lambda s: any(t["running"] and "target" in t
                             and trial_kind in t["path"] for t in s["trials"]),
                             "next " + trial_kind + " round", timeout=60)
        return next(t["target"] for t in state["trials"] if t["running"] and "target" in t
                    and trial_kind in t["path"])

    try:
        menu()
        click("menu_tab_settings")
        for _ in range(4):
            if any(b["id"] == "menu_start_over" for b in client.state()["buttons"]):
                break
            click("menu_next")
        capture("01-start-over")
        click("menu_start_over")
        capture("02-confirm-start-over")
        click("menu_start_over_yes")
        client.until(lambda s: s["task"] == "welcome" and any(o["id"] == "magic_ball" for o in s["objects"]),
                     "new game at dock")
        park("left")
        park()
        client.send("look", rotation=[-12, 0, 0])
        capture("03-welcome")
        client.send("move", hand="right", to="magic_ball", seconds=0.8)
        state = button("grip_click", True)
        check(state["waiting_for"] == "opened:menu", "Welcome ball grab did not advance")
        note("Welcome ball grabbed through controller input and Hand overlap")
        button("grip_click", False)
        menu()
        capture("04-welcome-menu")
        click("menu_tab_home")
        click("menu_close")
        park()
        client.send("look", rotation=[0, 0, 0])
        client.send("teleport", to="picnic")
        check(client.state()["task"] == "find_it", "Picnic did not start Find It")
        for round_index in range(5):
            obj = target("PicnicStation")
            if round_index == 0:
                # An intentional wrong pick exercises feedback and continued play.
                others = [o for o in client.state()["objects"] if o["id"] not in
                          [obj["id"], "PutAwayButton", "magic_ball"] and o["visible"]]
                check(bool(others), "No distractor on table")
                client.send("move", hand="right", to=others[0]["path"])
                button("grip_click", True)
                capture("05-find-it-wrong", at=obj["position"])
                button("grip_click", False)
                park()
            client.send("move", hand="right", to=obj["path"], seconds=0.8)
            if round_index == 0:
                capture("06-find-it-before-grab", at=obj["position"])
            state = button("grip_click", True)
            note(f"Find It round {round_index + 1}: target={obj['id']}; held_after_correct={state['hands']['right']['held']}")
            check(state["hands"]["right"]["held"] == "", "Correct pick stayed in the hand")
            if round_index == 0:
                time.sleep(0.5)
                state = client.send("move", hand="right",
                                    position=[obj["position"][0], obj["position"][1] + 0.15,
                                              obj["position"][2]], seconds=0.15)["state"]
                lifted = next(o for o in state["objects"] if o["path"] == obj["path"])
                check(abs(lifted["position"][1] - obj["position"][1] - 0.25) < 0.02,
                      "Correct pick did not finish its independent lift")
                note("Correct pick stays lifted after the gripping hand moves 15 cm")
                capture("07-find-it-correct", at=obj["position"])
            button("grip_click", False)
            park()
            client.until(lambda s: len([e for e in s["recent"] if e["kind"] == "trial"])
                         or s["task"] != "find_it", "round result")
            time.sleep(1.9)
        client.until(lambda s: s["task"] == "butterflies", "Find It reward and next task")
        capture("08-find-it-finished")
        client.send("teleport", to="meadow")
        for round_index in range(5):
            obj = target("MeadowStation")
            started_at = max((e["ms"] for e in client.state()["recent"]), default=-1)
            if round_index == 0:
                capture("09-butterfly", at=obj["position"], offset=[0, 0.15, 0.65])
            # Chase using fresh observations: the creature moves while the hand reaches.
            for attempt in range(10):
                client.send("move", hand="right", to="butterfly", seconds=0.18)
                state = client.state()
                if not any(t["running"] and "MeadowStation" in t["path"] for t in state["trials"]):
                    break
            else:
                raise AssertionError("Could not touch moving butterfly")
            outcomes = [e for e in state["recent"] if e["kind"] == "trial" and e["ms"] > started_at]
            check(bool(outcomes) and outcomes[-1]["data"]["data"].get("result") == "caught",
                  "Butterfly round ended without a catch")
            note(f"Butterfly round {round_index + 1}: physical hand contact")
            park()
            time.sleep(1.9)
        client.until(lambda s: s["task"] == "first_furniture", "butterfly reward")
        capture("meadow-sign-eyes")
        menu()
        click("menu_tab_shop")
        capture("10-shop-before")
        state = click("menu_buy_chair")
        check(state["inventory"].get("chair") == 1, "Chair not bought")
        capture("11-shop-purchased")
        click("menu_tab_bag")
        capture("12-bag-owned")
        click("menu_tab_home")
        click("menu_close")
        park()
        client.send("teleport", to="home")
        menu()
        click("menu_tab_bag")
        click("menu_take_out_chair")
        check(client.state()["hands"]["right"]["held"] == "chair", "Chair did not land in hand")
        home = client.state()["places"]["home"]
        client.send("move", hand="right", position=[home[0] + 0.5, 1.0, home[2] - 0.6], seconds=1)
        # Bag automatically puts furniture into a hand, even with grip initially up.
        button("grip_click", True)
        button("grip_click", False)
        client.until(lambda s: s["task"] == "", "furniture task completion")
        chair = next(o for o in client.state()["objects"] if o["id"] == "chair")
        capture("13-chair-placed", at=chair["position"], offset=[1.7, 1.6, 2])
        client.send("move", hand="right", to=chair["path"])
        state = button("grip_click", True)
        check(state["hands"]["right"]["held"] == "chair", "Could not pick chair back up")
        capture("14-chair-put-away-button", at=chair["position"], offset=[1.7, 1.8, 2])
        client.send("poke", hand="left", to="put_away")
        check(client.state()["inventory"].get("chair") == 1, "Chair not returned to bag")
        button("grip_click", False)
        park("left")
        park()
        menu()
        click("menu_tab_bag")
        capture("15-bag-returned")
        click("menu_tab_tasks")
        capture("16-repeatable-tasks")
        note("Interaction sequence finished. PNGs require visual review; this is not a visual PASS.")
    except Exception as error:
        note("STOPPED: " + str(error))
        capture("failure")
        raise


if __name__ == "__main__":
    main()
