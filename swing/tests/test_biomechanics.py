"""Self-tests for the biomechanics fault layer (synthetic poses, no data/model).
Run: python3 -m swing.tests.test_biomechanics   (also pytest-compatible)"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from swing.biomechanics import analyze, spine_tilt

def _pose(ms_x, mh_x, nose_x, sw=40, sh_y=100, hip_y=160, nose_y=70):
    """Build a pose with mid-shoulder x = ms_x, mid-hip x = mh_x, nose x = nose_x."""
    return {"nose": (nose_x, nose_y),
            "left_shoulder": (ms_x - sw/2, sh_y), "right_shoulder": (ms_x + sw/2, sh_y),
            "left_hip": (mh_x - 10, hip_y), "right_hip": (mh_x + 10, hip_y)}

CASES = []
def case(fn): CASES.append(fn); return fn

@case
def test_clean_swing_no_faults():
    poses = {"Address": _pose(105, 100, 100),
             "Top":     _pose(105, 100, 105),   # head steady
             "Impact":  _pose(105, 100, 100)}   # spine + hips stable
    f = analyze(poses)
    assert f == [], f

@case
def test_sway_off_ball_flagged():
    poses = {"Address": _pose(105, 100, 100),
             "Top":     _pose(105, 100, 130)}   # nose slides 30px = 0.75 SW
    names = [x["fault"] for x in analyze(poses)]
    assert "sway_off_ball" in names, names

@case
def test_early_extension_flagged():
    poses = {"Address": _pose(125, 100, 100),   # spine tilt ~22.6 deg
             "Top":     _pose(125, 100, 100),   # steady head (no sway)
             "Impact":  _pose(103, 100, 100)}   # spine tilt ~2.9 deg -> drop ~20 deg
    names = [x["fault"] for x in analyze(poses)]
    assert "early_extension" in names and "sway_off_ball" not in names, names

@case
def test_hip_slide_flagged():
    poses = {"Address": _pose(105, 100, 100),
             "Impact":  _pose(105, 135, 100)}   # mid-hip slides 35px = 0.875 SW
    names = [x["fault"] for x in analyze(poses)]
    assert "hip_slide" in names, names

@case
def test_spine_tilt_geometry():
    # mid-shoulder 25px right of mid-hip over 60px vertical -> ~22.6 deg
    p = _pose(125, 100, 100)
    assert abs(spine_tilt(p) - 22.6) < 1.0, spine_tilt(p)

if __name__ == "__main__":
    passed = 0
    for fn in CASES:
        try:
            fn(); passed += 1; print(f"PASS {fn.__name__}")
        except AssertionError as e:
            print(f"FAIL {fn.__name__}: {e}")
    print(f"\n{passed}/{len(CASES)} passed")
    sys.exit(0 if passed == len(CASES) else 1)
