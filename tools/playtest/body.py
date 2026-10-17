"""Pure geometry/policy for simulated seated users. No Godot or game-specific IDs."""

from dataclasses import asdict, dataclass
import json
import math
from pathlib import Path


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, k):
    return tuple(x * k for x in a)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def length(a):
    return math.sqrt(dot(a, a))


def unit(a):
    return mul(a, 1 / length(a))


def distance(a, b):
    return length(sub(a, b))


def transform(basis, offset):
    return tuple(sum(basis[j][i] * offset[j] for j in range(3)) for i in range(3))


class ConstraintError(AssertionError):
    def __init__(self, code, **evidence):
        self.code = code
        self.evidence = evidence
        super().__init__(f"{code}: {json.dumps(evidence, sort_keys=True)}")


def require(condition, code, **evidence):
    if not condition:
        raise ConstraintError(code, **evidence)


@dataclass(frozen=True)
class Limits:
    horizontal_fov: float
    vertical_fov: float
    view_margin: float
    max_head_yaw: float
    max_head_pitch: float
    min_target_degrees: float
    min_clear_fraction: float
    max_hand_speed: float
    hand_radius: float
    torso_radius: float
    sample_seconds: float
    path_step: float
    anchor_tolerance: float

    def __post_init__(self):
        if any(not math.isfinite(value) or value <= 0 for key, value in asdict(self).items()
               if key != "view_margin"):
            raise ValueError("Limits must be finite and positive")
        if not 0 <= self.view_margin < min(self.horizontal_fov, self.vertical_fov) / 2:
            raise ValueError("View margin must leave a visible region")
        if max(self.horizontal_fov, self.vertical_fov) >= 180 or self.min_clear_fraction > 1:
            raise ValueError("FOV must be below 180 degrees and clear fraction at most 1")


@dataclass(frozen=True)
class BodyProfile:
    name: str
    eye_height: float
    shoulder_half_width: float
    shoulder_drop: float
    arm_length: float
    comfortable_reach: float

    def __post_init__(self):
        if any(not math.isfinite(value) or value <= 0 for key, value in asdict(self).items() if key != "name"):
            raise ValueError("Body dimensions must be finite and positive")
        if not 0 < self.comfortable_reach <= self.arm_length:
            raise ValueError("comfortable_reach must be positive and no greater than arm_length")


def load_profiles(path=Path(__file__).with_name("body_profiles.json")):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    return [BodyProfile(**p) for p in data["profiles"]], Limits(**data["limits"]), data["assumptions"]


class Body:
    """Torso stays fixed during an action; head rotation never rotates shoulders."""

    def __init__(self, profile, limits, pose):
        self.profile = profile
        self.limits = limits
        self.origin = tuple(pose["rig_position"])
        self.basis = pose["rig_basis"]
        # Capture the seated eye location independently of subsequent head movement.
        self.neck = tuple(pose["eye"])

    def local_point(self, point):
        return add(self.origin, transform(self.basis, point))

    def shoulder(self, side):
        return add(self.neck, transform(self.basis, (
            self.profile.shoulder_half_width * (-1 if side == "left" else 1),
            -self.profile.shoulder_drop, 0)))

    def reach(self, side, point, comfortable=True):
        measured = distance(self.shoulder(side), point)
        maximum = self.profile.comfortable_reach if comfortable else self.profile.arm_length
        require(measured <= maximum + 1e-6, "reach", hand=side,
                measured=measured, limit=maximum, profile=self.profile.name, point=point)

    def hand(self, side, point):
        self.reach(side, point)
        # Vertical torso capsule below the shoulders; hand sphere may not enter it.
        top = add(self.neck, transform(self.basis, (0, -self.profile.shoulder_drop - 0.06, 0.04)))
        bottom = add(top, transform(self.basis, (0, -0.4, 0)))
        axis = sub(bottom, top)
        t = max(0, min(1, dot(sub(point, top), axis) / dot(axis, axis)))
        clearance = distance(point, add(top, mul(axis, t)))
        require(clearance >= self.limits.torso_radius + self.limits.hand_radius,
                "torso", hand=side, clearance=clearance)

    def posture(self, pose):
        require(distance(pose["rig_position"], self.origin) < 0.005,
                "body_moved", start=self.origin, actual=pose["rig_position"])
        require(all(distance(a, b) < 0.005 for a, b in zip(self.basis, pose["rig_basis"])),
                "body_turned")
        require(distance(pose["eye"], self.neck) < 0.03, "head_translated",
                start=self.neck, actual=pose["eye"])
        forward = mul(pose["eye_basis"][2], -1)
        local = tuple(dot(forward, axis) for axis in self.basis)
        yaw = math.degrees(math.atan2(local[0], -local[2]))
        pitch = math.degrees(math.atan2(local[1], math.hypot(local[0], local[2])))
        require(abs(yaw) <= self.limits.max_head_yaw + 1e-4, "head_yaw", degrees=yaw)
        require(abs(pitch) <= self.limits.max_head_pitch + 1e-4, "head_pitch", degrees=pitch)
        for side, hand in pose["hands"].items():
            require(self.limits.hand_radius + 1e-6 >= hand["radius"], "hand_radius_underestimated",
                    configured=self.limits.hand_radius, actual=hand["radius"])
            self.hand(side, hand["position"])
        self.hand_clearance(pose["hands"]["left"]["position"],
                            pose["hands"]["right"]["position"])

    def hand_clearance(self, point, other):
        clearance = distance(point, other)
        require(clearance + 1e-6 >= 2 * self.limits.hand_radius, "hands_overlap",
                clearance=clearance, minimum=2 * self.limits.hand_radius)

    def target(self, pose, target, side, whole_visual=True, reachable=True):
        require(target["visible"], "hidden", target=target["path"])
        require(side in target["allowed_hands"], "wrong_hand", hand=side, target=target["path"])
        if reachable:
            self.reach(side, self.contact(side, target))
        relative = sub(target["point"], pose["eye"])
        x, y, z = (dot(relative, axis) for axis in pose["eye_basis"])
        require(z < 0, "behind_view", target=target["path"])
        horizontal = abs(math.degrees(math.atan2(x, -z)))
        vertical = abs(math.degrees(math.atan2(y, -z)))
        # Fit the marker's entire projected bounding box, not just its centre.
        corners = target["visual_corners"]
        if not whole_visual:
            # A grasp needs the contact region in view, not an entire tall piece of furniture.
            corners = [add(target["point"], add(mul(pose["eye_basis"][0], x * self.limits.hand_radius),
                                                mul(pose["eye_basis"][1], y * self.limits.hand_radius)))
                       for x, y in ((-1, -1), (-1, 1), (1, -1), (1, 1))] if corners else []
        projected = [tuple(dot(sub(p, pose["eye"]), axis) for axis in pose["eye_basis"])
                     for p in corners]
        require(bool(projected), "no_visual", target=target["path"])
        require(all(p[2] < 0 for p in projected), "behind_view", target=target["path"])
        angles_x = [math.degrees(math.atan2(p[0], -p[2])) for p in projected]
        angles_y = [math.degrees(math.atan2(p[1], -p[2])) for p in projected]
        extent_x = max(map(abs, angles_x)) if whole_visual else horizontal
        extent_y = max(map(abs, angles_y)) if whole_visual else vertical
        require(extent_x <= self.limits.horizontal_fov / 2 - self.limits.view_margin
                and extent_y <= self.limits.vertical_fov / 2 - self.limits.view_margin,
                "view_angle", horizontal=horizontal, vertical=vertical)
        size = min(max(angles_x) - min(angles_x), max(angles_y) - min(angles_y))
        require(size >= self.limits.min_target_degrees, "angular_size", degrees=size,
                minimum=self.limits.min_target_degrees)
        fraction = target["clear_fraction"]
        require(fraction >= self.limits.min_clear_fraction, "occluded", clear_fraction=fraction,
                blockers=target["blockers"])

    def contact(self, side, target):
        """Stop at the near contact surface; hands need not enter a button's centre."""
        overlap = max(0, target["touch_radius"] + self.limits.hand_radius - 0.015)
        approach = target.get("approach") or unit(sub(self.shoulder(side), target["point"]))
        return add(target["point"], mul(approach, overlap))

    def path(self, side, start, end, other_hand=None):
        if other_hand is not None:
            # Closest point on the whole segment catches collisions between samples.
            # Actor moves one hand at a time, so the other hand stays stationary.
            motion = sub(end, start)
            squared = dot(motion, motion)
            t = max(0, min(1, dot(sub(other_hand, start), motion) / squared)) if squared else 0
            self.hand_clearance(add(start, mul(motion, t)), other_hand)
        steps = max(1, math.ceil(distance(start, end) / self.limits.path_step))
        points = [add(start, mul(sub(end, start), i / steps)) for i in range(steps + 1)]
        for point in points:
            self.hand(side, point)
        return points

    def describe(self):
        return {"profile": asdict(self.profile), "limits": asdict(self.limits),
                "origin": self.origin, "neck": self.neck, "basis": self.basis}
