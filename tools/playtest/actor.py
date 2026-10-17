"""Constrained actions for scenario authors. Raw Client is fixture/functional tooling only."""

from contextlib import contextmanager
import json
import math
import re
from pathlib import Path
import time

from body import Body, ConstraintError, add, sub, mul, dot, distance, require, transform, unit


class Report:
    def __init__(self, out, assumptions):
        self.out = Path(out)
        self.out.mkdir(parents=True, exist_ok=True)
        self.assumptions = assumptions
        self.cases = []
        self.expected_count = None
        self.profiles = {}
        self.started = time.monotonic()
        self.trace = (self.out / "body-trace.jsonl").open("w", encoding="utf-8")

    def record(self, kind, **data):
        if kind == "body":
            self.profiles[data["profile"]["name"]] = {"profile": data["profile"], "limits": data["limits"]}
        self.trace.write(json.dumps({"time": time.time(), "kind": kind, **data}) + "\n")
        self.trace.flush()

    @contextmanager
    def case(self, name, expected_codes=()):
        self.record("case", name=name, expected_codes=expected_codes)
        fatal = None
        try:
            yield
        except ConstraintError as error:
            passed = error.code in expected_codes
            result = {"name": name, "passed": passed, "expected_rejection": bool(expected_codes),
                      "code": error.code, "evidence": error.evidence}
        except Exception as error:
            result = {"name": name, "passed": False, "error": repr(error)}
            fatal = error
        else:
            result = {"name": name, "passed": not expected_codes,
                      "error": "Fault was not detected" if expected_codes else ""}
        self.cases.append(result)
        self.record("result", **result)
        print(f"{'PASS' if result['passed'] else 'FAIL'} {name}: {result.get('code', result.get('error', ''))}", flush=True)
        self.save()
        if fatal:
            raise fatal

    def save(self):
        complete = self.expected_count is None or len(self.cases) == self.expected_count
        passed = complete and bool(self.cases) and all(case["passed"] for case in self.cases)
        (self.out / "body-report.json").write_text(json.dumps({
            "passed": passed, "scope": "Constrained geometry and real controller/collision regression",
            "assumptions": self.assumptions, "profiles": list(self.profiles.values()),
            "completed": len(self.cases), "expected": self.expected_count, "cases": self.cases,
            "elapsed_seconds": round(time.monotonic() - self.started, 3),
            "limitations": ["Synthetic shoulder/torso model; no elbow or joint biomechanics",
                            "Occlusion uses physics collision proxies, not pixel visibility",
                            "Configured view cone is not measured device per-eye FOV",
                            "Headset comfort, recognition and readability require human validation"]
        }, indent=2) + "\n", encoding="utf-8")
        return passed

    def engine_result(self, returncode):
        errors = []
        for name in ("godot.log", "console.log"):
            path = self.out / name
            if not path.exists():
                errors.append("Missing engine log: " + name)
                continue
            errors.extend(re.findall(r"^(?:SCRIPT ERROR|ERROR):.*", path.read_text(encoding="utf-8"), re.MULTILINE))
        if returncode or errors:
            self.cases.append({"name": "engine_session", "passed": False,
                               "returncode": returncode, "errors": errors})

    def close(self):
        self.trace.close()


class Actor:
    def __init__(self, client, profile, limits, report):
        self._client = client
        self.report = report
        self.body = Body(profile, limits, self.observe()["pose"])
        self.watches = {}
        report.record("body", **self.body.describe())
        self.body.posture(self.observe()["pose"])

    def observe(self, targets=()):
        return self._client.send("observe", targets=list(targets))["observation"]

    def target(self, key, side, whole_visual=True):
        observation = self.observe([key])
        self.body.posture(observation["pose"])
        target = observation["targets"][key]
        require(target is not None, "missing_target", target=key)
        self.body.target(observation["pose"], target, side, whole_visual)
        return target

    def watch(self, key, side, stable=False):
        target = self.target(key, side)
        self.watches[target["path"]] = (side, target["position"] if stable else None)
        return target

    def _check(self, observation):
        self.report.record("sample", observation=observation)
        self.body.posture(observation["pose"])
        for path, (side, anchor) in self.watches.items():
            target = observation["targets"][path]
            require(target is not None, "missing_target", target=path)
            if anchor is not None:
                drift = distance(target["position"], anchor)
                require(drift <= self.body.limits.anchor_tolerance,
                        "target_moved", target=path, drift=drift, anchor=anchor)
            self.body.target(observation["pose"], target, side)

    def move(self, side, position, contact=None, touching=None):
        """Preflight the whole path, then sweep and observe every bounded step."""
        observation = self.observe(self.watches)
        self._check(observation)
        start = observation["pose"]["hands"][side]["position"]
        other = "left" if side == "right" else "right"
        points = self.body.path(side, start, position,
                                other_hand=observation["pose"]["hands"][other]["position"])
        require(self._client.send("probe", hand=side, points=points,
                                 radius=self.body.limits.hand_radius, contact=contact or "")["probe"]["clear"],
                "path_blocked", hand=side, start=start, end=position)
        duration = max(self.body.limits.sample_seconds,
                       distance(start, position) / self.body.limits.max_hand_speed)
        result = self._client.send("step", hand=side, position=position, seconds=duration,
                                   targets=list(self.watches),
                                   guard={"radius": self.body.limits.hand_radius, "contact": contact or ""})
        completed = False
        for sample in result["samples"]:
            require("blocked" not in sample, "path_blocked", hand=side, evidence=sample.get("blocked"))
            if touching and not completed:
                latest = sample["targets"].get(touching["path"])
                if latest is None or not latest["visible"] or latest.get("done", False):
                    separation = distance(sample["pose"]["hands"][side]["position"], touching["point"])
                    require(separation <= touching["touch_radius"] + self.body.limits.hand_radius + 0.025,
                            "target_disappeared_before_contact", separation=separation)
                    self.watches.pop(touching["path"], None)
                    completed = True
                else:
                    touching = latest
            self._check(sample)
        self._check(result["observation"])
        return result["observation"]

    def grab(self, key, side, consumed=False):
        require(not self.observe()["pose"]["hands"][side]["held"], "hand_busy", hand=side)
        observation = self.observe([key])
        target = observation["targets"][key]
        require(target is not None, "missing_target", target=key)
        surface = target["grasp"][side]
        require(bool(surface), "unsupported_grasp_shape", target=key)
        target = {**target, **surface, "touch_radius": 0}
        self.body.target(observation["pose"], target, side, whole_visual=False)
        self.move(side, self.body.contact(side, target), contact=target["path"])
        self._client.send("button", hand=side, action="grip_click", pressed=True)
        observation = self.observe(self.watches)
        self._check(observation)
        if not consumed:
            require(observation["pose"]["hands"][side]["held_path"] == target["path"], "grab_failed", target=key, hand=side)
        return target

    def release(self, side):
        self._client.send("button", hand=side, action="grip_click", pressed=False)
        observation = self.observe(self.watches)
        self._check(observation)
        require(not observation["pose"]["hands"][side]["held"], "release_failed", hand=side)

    def touch(self, key, side):
        target = self.target(key, side)
        # The observed target may disappear as a valid result of contact.
        # Its functional outcome is asserted by the scenario, never manufactured here.
        path = target["path"]
        self.watches.setdefault(path, (side, None))
        self.move(side, self.body.contact(side, target), touching=target)
        self.report.record("touch", hand=side, target=path)

    def miss_touch(self, key, side, clearance=.08):
        """Reproducible undershoot; never replace the endpoint with the target centre."""
        target = self.target(key, side)
        start = self.observe()["pose"]["hands"][side]["position"]
        radius = target["touch_radius"] + self.body.limits.hand_radius
        require(distance(start, target["point"]) > radius, "miss_started_in_contact", target=key)
        endpoint = add(target["point"], mul(unit(sub(start, target["point"])), radius + clearance))
        self.move(side, endpoint)
        latest = self.observe([key])["targets"][key]
        require(latest is not None and latest["visible"] and not latest.get("done", False),
                "miss_consumed_target", target=key)
        self.report.record("touch_attempt", target=target["path"], miss=True, endpoint=endpoint,
                           clearance=clearance, actual_target=latest["point"])
        return latest

    def wrist_menu(self, miss=False):
        target = self.target("star", "right")
        self.look_at(target["point"])
        # Touch with a fingertip, leaving the two controller spheres separate.
        offset = (.24 if miss else .10, .065, 0)
        endpoint = add(target["point"], transform(self.body.basis, offset))
        self.move("right", endpoint)
        self.aim("right", target["point"])
        self.expect(lambda s: s["menu_open"] != miss, "wrist miss/open outcome")
        self.report.record("wrist_attempt", miss=miss, endpoint=endpoint)

    def rotate(self, side, rotation):
        position = self.observe()["pose"]["hands"][side]["position"]
        result = self._client.send("step", hand=side, position=position, rotation=rotation,
                                   seconds=0.12, targets=list(self.watches))
        for sample in result["samples"]:
            self._check(sample)

    def look(self, pitch=0, yaw=0):
        require(abs(pitch) <= self.body.limits.max_head_pitch, "head_pitch", degrees=pitch)
        require(abs(yaw) <= self.body.limits.max_head_yaw, "head_yaw", degrees=yaw)
        observation = self._client.send("head", rotation=[pitch, yaw, 0],
                                         targets=list(self.watches))["observation"]
        self._check(observation)

    def expect(self, predicate, description):
        require(predicate(self._client.state()), "outcome", description=description)

    def button(self, side, action, pressed):
        self._check(self.observe(self.watches))
        result = self._client.send("button", hand=side, action=action, pressed=pressed, seconds=0.04)
        self._check(self.observe(self.watches))
        return result["state"]

    def park(self, side, contact=None):
        height = self.body.profile.eye_height
        return self.move(side, self.body.local_point((-.22 if side == "left" else .22, height - .30, -.20)),
                         contact=contact)

    def look_at(self, point):
        delta = sub(point, self.body.neck)
        x, y, z = (dot(delta, axis) for axis in self.body.basis)
        yaw = math.degrees(math.atan2(-x, -z))
        pitch = math.degrees(math.atan2(y, math.hypot(x, z)))
        self.look(pitch=max(-self.body.limits.max_head_pitch, min(self.body.limits.max_head_pitch, pitch)),
                  yaw=max(-self.body.limits.max_head_yaw, min(self.body.limits.max_head_yaw, yaw)))

    def aim(self, side, point):
        observation = self.observe(self.watches)
        self._check(observation)
        position = observation["pose"]["hands"][side]["position"]
        result = self._client.send("step", hand=side, position=position, aim_at=point,
                                   seconds=0.08, targets=list(self.watches))
        for sample in result["samples"]:
            self._check(sample)

    def click(self, key, side="right", miss=False):
        observed = self.observe([key])
        target = observed["targets"][key]
        require(target is not None, "missing_target", target=key)
        self.look_at(target["point"])
        self.body.target(self.observe()["pose"], target, side, reachable=False)
        point = target["point"]
        if miss:
            # Outside the tab's left edge; scenario chooses an outside-edge tab.
            point = add(point, mul(target["basis"][0], -target["ray_size"][0] / 2 - .025))
        self.button(side, "trigger_click", False)
        self.aim(side, point)
        before = self._client.state()["event_sequence"]
        self.button(side, "trigger_click", True)
        state = self.button(side, "trigger_click", False)
        presses = [e for e in state["recent"] if e["sequence"] > before
                   and e["kind"] == "fact" and e["data"].get("what") == "pressed"]
        require(not presses if miss else any(e["data"].get("id") == key for e in presses),
                "aim_miss_activated" if miss else "click_failed", target=key, presses=presses)
        self.report.record("aim_attempt", target=key, miss=miss, aim_point=point, presses=presses)
        return state

    def locomotion(self, axis, frames=3, side="right", destination=None):
        """Only controller-driven locomotion may change the actor's body anchor."""
        require(not self.watches, "locomotion_while_watching")
        before = self.observe()["pose"]
        self._check({"pose": before, "targets": {}})
        result = self._client.send("tracked_stick", hand=side, axis=axis, frames=frames)
        for sample in result["samples"]:
            pose = sample["pose"]
            # The rig may move, but tracked head/hands must retain their local poses.
            for name, point, old in [("eye", pose["eye"], before["eye"])] + [
                    (s, pose["hands"][s]["position"], before["hands"][s]["position"])
                    for s in ("left", "right")]:
                local = [dot(sub(point, pose["rig_position"]), a) for a in pose["rig_basis"]]
                previous = [dot(sub(old, before["rig_position"]), a) for a in before["rig_basis"]]
                require(distance(local, previous) < .005, "tracking_shift", part=name)
            self.body = Body(self.body.profile, self.body.limits, pose)
            self._check(sample)
        if destination is not None:
            require(distance(result["observation"]["pose"]["rig_position"], destination) < .12,
                    "teleport_landing", expected=destination,
                    actual=result["observation"]["pose"]["rig_position"])
        self.report.record("locomotion", axis=axis, frames=frames, side=side,
                           destination=destination, pose=result["observation"]["pose"])

    def face(self, point):
        self.look()
        for _ in range(7):
            delta = sub(point, self.body.neck)
            yaw = math.degrees(math.atan2(-dot(delta, self.body.basis[0]), -dot(delta, self.body.basis[2])))
            if abs(yaw) <= 20:
                return
            self.locomotion([-1 if yaw > 0 else 1, 0])
        require(False, "turn_failed", point=point)

    def teleport(self, point):
        self.face(point)
        self.look_at(point)
        self.aim("right", point)
        self.locomotion([0, 1], destination=point)

    def walk_to(self, point):
        self.look()
        for _ in range(50):
            delta = sub(point, self.body.origin)
            flat = (delta[0], 0, delta[2])
            remaining = distance(flat, (0, 0, 0))
            if remaining < .035:
                return
            direction = unit(flat)
            frames = max(2, min(30, round(remaining / .025)))
            old = self.body.origin
            self.locomotion([dot(direction, self.body.basis[0]), -dot(direction, self.body.basis[2])],
                            frames=frames, side="left")
            require(distance(old, self.body.origin) > .005, "walk_blocked", destination=point)
        require(False, "walk_timeout", destination=point)

    def wait_for(self, predicate, description, timeout=15):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            self._check(self.observe(self.watches))
            state = self._client.state()
            if predicate(state):
                return state
            time.sleep(.02) # readiness polling, never simulated hesitation
        require(False, "timeout", description=description)

    def capture(self, name):
        self._client.send("view", mode="eyes")
        result = self._client.send("capture", name=name)
        self.report.record("image", path=result["path"])
