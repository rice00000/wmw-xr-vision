"""Constrained actions for scenario authors. Raw Client is fixture/functional tooling only."""

from contextlib import contextmanager
import json
from pathlib import Path
import time

from body import Body, ConstraintError, distance, require


class Report:
    def __init__(self, out, assumptions):
        self.out = Path(out)
        self.out.mkdir(parents=True, exist_ok=True)
        self.assumptions = assumptions
        self.cases = []
        self.expected_count = None
        self.profiles = {}
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
            "limitations": ["Synthetic shoulder/torso model; no elbow or joint biomechanics",
                            "Occlusion uses physics collision proxies, not pixel visibility",
                            "Configured view cone is not measured device per-eye FOV",
                            "Headset comfort, recognition and readability require human validation"]
        }, indent=2) + "\n", encoding="utf-8")
        return passed

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
        points = self.body.path(side, start, position)
        require(self._client.send("probe", hand=side, points=points,
                                 radius=self.body.limits.hand_radius, contact=contact or "")["probe"]["clear"],
                "path_blocked", hand=side, start=start, end=position)
        for point in points[1:]:
            previous = observation["pose"]["hands"][side]["position"]
            probe = self._client.send("probe", hand=side, points=[previous, point],
                                      radius=self.body.limits.hand_radius, contact=contact or "")["probe"]
            require(probe["clear"], "path_blocked", hand=side, **probe)
            duration = max(self.body.limits.sample_seconds,
                           distance(previous, point) / self.body.limits.max_hand_speed)
            result = self._client.send("step", hand=side, position=point, seconds=duration,
                                        targets=list(self.watches))
            completed = False
            for sample in result["samples"]:
                if touching and not completed:
                    latest = sample["targets"][touching["path"]]
                    if latest is None or not latest["visible"]:
                        separation = distance(sample["pose"]["hands"][side]["position"], touching["point"])
                        require(separation <= touching["touch_radius"] + self.body.limits.hand_radius + 0.005,
                                "target_disappeared_before_contact", separation=separation)
                        self.watches.pop(touching["path"])
                        completed = True
                self._check(sample)
            observation = result["observation"]
            if completed:
                return observation
        return observation

    def grab(self, key, side):
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

    def capture(self, name):
        self._client.send("view", mode="eyes")
        result = self._client.send("capture", name=name)
        self.report.record("image", path=result["path"])
