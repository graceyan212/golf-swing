"""2D biomechanics fault layer: given pose keypoints at the detected swing events,
compute robust angles/offsets and flag faults vs good ranges.

Honest scope: single-view 2D proxies (true 3D rotation needs depth/multi-view).
These are the field-standard 2D checks — sway, hip slide, early extension — and
are still far beyond what a frontier model produces from a video. Faults are
COMPUTED from geometry (no fault labels required), the same "derive the ground
truth from math" idea as the strokes-gained solver in the caddie project.

Pose = dict {joint: (x, y)} in image pixels (x right, y down). Joint names follow
COCO-17: nose, left_shoulder, right_shoulder, left_hip, right_hip. (A
MediaPipe->COCO mapping lives in swing/pose.py.)
"""
from __future__ import annotations
import math

REQUIRED_JOINTS = ("nose", "left_shoulder", "right_shoulder", "left_hip", "right_hip")


def _mid(a, b): return ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)
def _dist(a, b): return math.hypot(a[0] - b[0], a[1] - b[1])
def mid_shoulder(p): return _mid(p["left_shoulder"], p["right_shoulder"])
def mid_hip(p): return _mid(p["left_hip"], p["right_hip"])
def shoulder_width(p): return max(_dist(p["left_shoulder"], p["right_shoulder"]), 1e-6)


def spine_tilt(p) -> float:
    """Lateral spine tilt (deg) from vertical: angle of the hip->shoulder line.
    0 = perfectly upright. In a face-on view this is side-bend away from target."""
    ms, mh = mid_shoulder(p), mid_hip(p)
    dx, dy = ms[0] - mh[0], ms[1] - mh[1]
    return math.degrees(math.atan2(abs(dx), abs(dy)))


def _lat(ref_pt, now_pt, sw) -> float:
    """Signed horizontal shift (in shoulder-widths); + = toward image-right."""
    return (now_pt[0] - ref_pt[0]) / sw


DEFAULT_THRESH = {"sway": 0.40, "slide": 0.70, "early_ext": 8.0}


def analyze(poses: dict, thresh: dict | None = None) -> list[dict]:
    """poses: {event_name: pose}. Uses Address/Top/Impact. Returns fault dicts
    with the measured value, threshold, and a plain-language note."""
    t = {**DEFAULT_THRESH, **(thresh or {})}
    faults = []
    A, T, I = poses.get("Address"), poses.get("Top"), poses.get("Impact")

    if A and T:
        sway = _lat(A["nose"], T["nose"], shoulder_width(A))
        if abs(sway) > t["sway"]:
            faults.append({"fault": "sway_off_ball", "events": ["Address", "Top"],
                           "value": round(sway, 2), "threshold": t["sway"],
                           "note": f"head slides {sway:+.2f} shoulder-widths on the "
                                   f"backswing (steady is within ±{t['sway']}) — you're "
                                   f"swaying off the ball instead of turning"})
    if A and I:
        slide = _lat(mid_hip(A), mid_hip(I), shoulder_width(A))
        if abs(slide) > t["slide"]:
            faults.append({"fault": "hip_slide", "events": ["Address", "Impact"],
                           "value": round(slide, 2), "threshold": t["slide"],
                           "note": f"hips slide {slide:+.2f} shoulder-widths laterally by "
                                   f"impact (>{t['slide']}) — driving past the ball instead "
                                   f"of rotating"})
        drop = spine_tilt(A) - spine_tilt(I)   # + = spine straightened toward vertical
        if drop > t["early_ext"]:
            faults.append({"fault": "early_extension", "events": ["Address", "Impact"],
                           "value": round(drop, 1), "threshold": t["early_ext"],
                           "note": f"spine straightens {drop:.0f}deg from address to impact "
                                   f"(>{t['early_ext']}) — early extension / standing up "
                                   f"through the shot"})
    return faults


def report(poses: dict, thresh: dict | None = None) -> str:
    faults = analyze(poses, thresh)
    if not faults:
        return "No major faults flagged (sway / hip slide / early extension within range)."
    return "Faults:\n" + "\n".join(f"  - {f['fault']}: {f['note']}" for f in faults)
