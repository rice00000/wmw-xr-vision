"""Boundary and fault tests for the test framework itself; no renderer required."""

from contextlib import redirect_stdout
from dataclasses import replace
import json
import io
import copy
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools" / "playtest"))
from actor import Actor, Report
from body import Body, ConstraintError, add, load_profiles


def pose():
    return {"eye": [0, 1.25, 0], "eye_basis": [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
            "rig_position": [0, 0, 0], "rig_basis": [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
            "hands": {side: {"position": [x, 0.90, -0.20], "held": "", "held_path": "", "radius": 0.07}
                      for side, x in (("left", -0.22), ("right", 0.22))}}


def target(point=(0, 1.05, -0.4), size=0.08):
    return {"id": "button", "path": "/button", "point": point, "position": point,
            "visible": True, "touch_radius": 0.07, "allowed_hands": ["left", "right"],
            "clear_fraction": 1.0, "blockers": [],
            "visual_corners": [add(point, (x * size / 2, y * size / 2, 0))
                               for x, y in ((-1, -1), (-1, 1), (1, -1), (1, 1))]}


class BodyTests(unittest.TestCase):
    def setUp(self):
        self.profiles, self.limits, _ = load_profiles()
        self.body = Body(self.profiles[1], self.limits, pose())

    def rejects(self, code, callback):
        with self.assertRaises(ConstraintError) as context:
            callback()
        self.assertEqual(context.exception.code, code)

    def test_valid_target_and_posture(self):
        self.body.posture(pose())
        for side in ("left", "right"):
            self.body.target(pose(), target(), side)

    def test_reach_boundary(self):
        shoulder = self.body.shoulder("right")
        self.body.reach("right", add(shoulder, (0, 0, -self.body.profile.comfortable_reach)))
        self.rejects("reach", lambda: self.body.reach(
            "right", add(shoulder, (0, 0, -self.body.profile.comfortable_reach - 0.001))))

    def test_maximum_extension_is_not_comfortable_reach(self):
        point = add(self.body.shoulder("right"), (0, 0, -self.body.profile.arm_length))
        self.body.reach("right", point, comfortable=False)
        self.rejects("reach", lambda: self.body.reach("right", point))

    def test_contact_surface_can_be_reachable_when_centre_is_not(self):
        button = target(add(self.body.shoulder("right"), (0, 0, -0.60)))
        self.body.reach("right", self.body.contact("right", button))
        self.rejects("reach", lambda: self.body.reach("right", button["point"]))

    def test_looking_at_a_target_does_not_extend_the_arm(self):
        self.rejects("reach", lambda: self.body.target(pose(), target((0, 1.0, -1.5)), "right"))

    def test_body_translation_rejected(self):
        moved = pose()
        moved["rig_position"][0] += 0.1
        self.rejects("body_moved", lambda: self.body.posture(moved))

    def test_head_translation_rejected(self):
        moved = pose()
        moved["eye"][0] += 0.1
        self.rejects("head_translated", lambda: self.body.posture(moved))

    def test_shoulders_do_not_follow_head_rotation(self):
        shoulder = self.body.shoulder("right")
        turned = pose()
        turned["eye_basis"] = [[0.866, 0, -0.5], [0, 1, 0], [0.5, 0, 0.866]]
        self.body.posture(turned)
        self.assertEqual(self.body.shoulder("right"), shoulder)

    def test_path_with_valid_endpoints_can_cross_torso(self):
        start, end = (0.25, 0.88, 0.04), (-0.25, 0.88, 0.04)
        self.body.hand("right", start)
        self.body.hand("right", end)
        self.rejects("torso", lambda: self.body.path("right", start, end))

    def test_behind_view(self):
        self.rejects("behind_view", lambda: self.body.target(pose(), target((0, 1.0, 0.25)), "right"))

    def test_view_angle(self):
        self.rejects("view_angle", lambda: self.body.target(pose(), target((0.30, 1.0, -0.10)), "right"))

    def test_marker_edges_must_fit_not_only_centre(self):
        self.rejects("view_angle", lambda: self.body.target(pose(), target(size=0.4), "right"))

    def test_tiny_marker(self):
        self.rejects("angular_size", lambda: self.body.target(pose(), target(size=0.001), "right"))

    def test_hidden_marker(self):
        button = target()
        button["visible"] = False
        self.rejects("hidden", lambda: self.body.target(pose(), button, "right"))

    def test_partial_occlusion_threshold(self):
        button = target()
        button["clear_fraction"] = self.limits.min_clear_fraction
        self.body.target(pose(), button, "left")
        button["clear_fraction"] -= 0.01
        self.rejects("occluded", lambda: self.body.target(pose(), button, "left"))

    def test_wrong_hand(self):
        button = target()
        button["allowed_hands"] = ["left"]
        self.rejects("wrong_hand", lambda: self.body.target(pose(), button, "right"))

    def test_invalid_profile_cannot_invent_extra_comfortable_reach(self):
        with self.assertRaises(ValueError):
            replace(self.profiles[0], comfortable_reach=2)

    def test_failed_preflight_sends_no_movement(self):
        class Transport:
            def __init__(self):
                self.commands = []

            def send(self, command, **_args):
                self.commands.append(command)
                return {"observation": {"pose": pose(), "targets": {}}}

        with tempfile.TemporaryDirectory() as out:
            report = Report(out, "test")
            transport = Transport()
            actor = Actor(transport, self.profiles[1], self.limits, report)
            self.rejects("reach", lambda: actor.move("right", (0, 3, -1)))
            self.assertNotIn("step", transport.commands)
            report.close()

    def test_wrong_rejection_does_not_pass_a_negative_case(self):
        with tempfile.TemporaryDirectory() as out:
            report = Report(out, "test")
            with redirect_stdout(io.StringIO()), report.case("broken checker", ("reach",)):
                raise ConstraintError("unrelated_failure")
            self.assertFalse(report.save())
            saved = json.loads((Path(out) / "body-report.json").read_text(encoding="utf-8"))
            self.assertFalse(saved["passed"])
            report.close()

    def test_undetected_fault_does_not_pass_a_negative_case(self):
        with tempfile.TemporaryDirectory() as out:
            report = Report(out, "test")
            with redirect_stdout(io.StringIO()), report.case("missed fault", ("reach",)):
                pass
            self.assertFalse(report.save())
            report.close()

    def test_incomplete_suite_cannot_report_pass(self):
        with tempfile.TemporaryDirectory() as out:
            report = Report(out, "test")
            report.expected_count = 2
            with redirect_stdout(io.StringIO()), report.case("only one ran"):
                pass
            self.assertFalse(report.save())
            report.close()

    def test_underestimated_hand_size_is_rejected(self):
        observed = pose()
        observed["hands"]["right"]["radius"] = 0.09
        self.rejects("hand_radius_underestimated", lambda: self.body.posture(observed))

    def test_invalid_speed_limit_is_rejected(self):
        with self.assertRaises(ValueError):
            replace(self.limits, max_hand_speed=0)

    def test_overlapping_hands_are_rejected(self):
        observed = pose()
        for hand in observed["hands"].values():
            hand["position"] = [0, 1.05, -0.3]
        self.rejects("hands_overlap", lambda: self.body.posture(observed))

    def test_hand_clearance_boundary(self):
        point = (0, 1.05, -0.3)
        self.body.hand_clearance(point, add(point, (2 * self.limits.hand_radius, 0, 0)))
        self.rejects("hands_overlap", lambda: self.body.hand_clearance(
            point, add(point, (2 * self.limits.hand_radius - 0.001, 0, 0))))

    def test_hand_path_checks_between_samples(self):
        # A coarse path has only its two clear endpoints, but crosses the other hand.
        body = Body(self.profiles[1], replace(self.limits, path_step=1), pose())
        start, end, other = (-0.20, 1.05, -0.3), (0.20, 1.05, -0.3), (0, 1.05, -0.3)
        body.path("right", start, end)
        body.hand_clearance(start, other)
        body.hand_clearance(end, other)
        self.rejects("hands_overlap", lambda: body.path("right", start, end, other_hand=other))

    def test_stationary_hand_path_still_checks_clearance(self):
        point = (0, 1.05, -0.3)
        self.body.path("right", point, point, other_hand=(-0.2, 1.05, -0.3))
        self.rejects("hands_overlap", lambda: self.body.path("right", point, point, other_hand=point))

    def test_hand_collision_preflight_sends_no_movement(self):
        class Transport:
            def __init__(self):
                self.commands = []

            def send(self, command, **_args):
                self.commands.append(command)
                return {"observation": {"pose": pose(), "targets": {}}}

        with tempfile.TemporaryDirectory() as out:
            report = Report(out, "test")
            transport = Transport()
            actor = Actor(transport, self.profiles[1], self.limits, report)
            self.rejects("hands_overlap", lambda: actor.move("right", (-0.20, 0.90, -0.20)))
            self.assertNotIn("step", transport.commands)
            self.assertNotIn("probe", transport.commands)
            report.close()

    def test_ray_target_does_not_require_touch_reach(self):
        button = target((0, 1.05, -1.0), size=.12)
        self.rejects("reach", lambda: self.body.target(pose(), button, "right"))
        self.body.target(pose(), button, "right", reachable=False)

    def test_continuous_move_batches_transport_and_checks_intermediate_samples(self):
        class Transport:
            bad_sample = False

            def __init__(self):
                self.commands = []

            def send(self, command, **args):
                self.commands.append((command, args))
                if command == "probe":
                    return {"probe": {"clear": True}}
                observed = {"pose": pose(), "targets": {}}
                if command == "step":
                    observed["pose"]["hands"]["right"]["position"] = args["position"]
                    middle = copy.deepcopy(observed)
                    if self.bad_sample:
                        middle["pose"]["hands"]["right"]["position"] = [0, 3, 0]
                    return {"observation": observed, "samples": [middle, observed]}
                return {"observation": observed}

        with tempfile.TemporaryDirectory() as out:
            report = Report(out, "test")
            transport = Transport()
            actor = Actor(transport, self.profiles[1], self.limits, report)
            actor.move("right", (.22, .90, -.40))
            steps = [args for command, args in transport.commands if command == "step"]
            self.assertEqual(len(steps), 1)
            self.assertEqual(steps[0]["guard"]["radius"], self.limits.hand_radius)
            self.assertGreaterEqual(steps[0]["seconds"], .2 / self.limits.max_hand_speed)
            transport.bad_sample = True
            self.rejects("reach", lambda: actor.move("right", (.22, .90, -.40)))
            report.close()

    def test_continuous_move_rejects_engine_collision_guard(self):
        class Transport:
            def send(self, command, **args):
                if command == "probe":
                    return {"probe": {"clear": True}}
                observed = {"pose": pose(), "targets": {}}
                if command == "step":
                    return {"observation": observed, "samples": [{"blocked": {"clear": False}}]}
                return {"observation": observed}

        with tempfile.TemporaryDirectory() as out:
            report = Report(out, "test")
            actor = Actor(Transport(), self.profiles[1], self.limits, report)
            self.rejects("path_blocked", lambda: actor.move("right", (.22, .90, -.4)))
            report.close()

    def test_infrastructure_failure_is_recorded_and_stops_the_suite(self):
        with tempfile.TemporaryDirectory() as out:
            report = Report(out, "test")
            with self.assertRaises(ConnectionError), redirect_stdout(io.StringIO()):
                with report.case("engine disconnected", ("reach",)):
                    raise ConnectionError("connection lost")
            self.assertFalse(report.save())
            self.assertIn("connection lost", report.cases[0]["error"])
            report.close()


if __name__ == "__main__":
    unittest.main()
