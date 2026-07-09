"""Self-tests for swing.eval (the GolfDB PCE metric).

No dataset, no torch, no GPU — pure numpy metric logic. Run either way::

    python3 -m swing.tests.test_eval      # standalone assert runner
    pytest swing/tests/test_eval.py       # pytest also collects the test_* fns

The reference tolerance formula being verified (GolfDB, vendor/GolfDB/util.py::
correct_preds) is::

    tol = int(max(np.round((events[5] - events[0]) / 30), 1))
    correct = (np.abs(events - preds) <= tol)
"""

import numpy as np

from swing.eval import (
    EVENTS,
    N_EVENTS,
    event_tolerance,
    events_from_probs,
    format_scorecard,
    score_dataset,
    score_swing,
)

# A canonical ground-truth swing. Address=0, Impact=60 -> span 60 -> tol = 2,
# which gives clean on/inside/outside boundaries at deltas 2/1/3.
TRUE = np.array([0, 12, 24, 36, 48, 60, 90, 120])


def test_events_constant_is_the_eight_ordered_events():
    assert EVENTS == [
        "Address",
        "Toe-up",
        "Mid-backswing",
        "Top",
        "Mid-downswing",
        "Impact",
        "Mid-follow-through",
        "Finish",
    ]
    assert N_EVENTS == 8


def test_perfect_predictions_score_100():
    trues = np.array([TRUE, TRUE + 3, TRUE + 7])
    preds = trues.copy()
    card = score_dataset(preds, trues)
    assert card["pce"] == 100.0
    assert card["n_correct"] == card["n_events"] == 3 * N_EVENTS
    for name in EVENTS:
        assert card["per_event"][name] == 100.0


def test_far_off_predictions_score_0():
    trues = np.array([TRUE, TRUE, TRUE])
    preds = trues + 500  # nowhere near any tolerance
    card = score_dataset(preds, trues)
    assert card["pce"] == 0.0
    assert card["n_correct"] == 0
    for name in EVENTS:
        assert card["per_event"][name] == 0.0


def test_tolerance_boundary_on_inside_outside():
    # span = 60 -> tol = 2. Check the three cases around the boundary directly.
    assert event_tolerance(TRUE) == 2

    inside = TRUE.copy()
    inside[3] = TRUE[3] + 1          # delta 1 < tol  -> correct
    on = TRUE.copy()
    on[3] = TRUE[3] + 2              # delta 2 == tol -> correct (GolfDB uses <=)
    outside = TRUE.copy()
    outside[3] = TRUE[3] + 3         # delta 3 > tol  -> incorrect

    assert bool(score_swing(inside, TRUE)[3]) is True
    assert bool(score_swing(on, TRUE)[3]) is True
    assert bool(score_swing(outside, TRUE)[3]) is False

    # Symmetry: undershooting by the same amounts behaves identically.
    assert bool(score_swing(TRUE - 2, TRUE)[3]) is True
    assert bool(score_swing(TRUE - 3, TRUE)[3]) is False


def test_per_event_breakdown():
    # One perfect swing + one swing with a controlled per-event pattern (tol=2):
    #   deltas per event: [0, 2, 3, 1, 2, 3, 0, 0]
    #   correct pattern : [T, T, F, T, T, F, T, T]
    perfect = TRUE.copy()
    mixed = np.array([0, 14, 21, 37, 50, 63, 90, 120])
    expected_mixed = [True, True, False, True, True, False, True, True]
    assert list(score_swing(mixed, TRUE)) == expected_mixed

    card = score_dataset([perfect, mixed], [TRUE, TRUE])
    # Address/Toe-up/Top/Mid-downswing/follow-through/Finish: both correct -> 100
    # Mid-backswing & Impact: perfect correct, mixed wrong -> 50
    expected_per_event = {
        "Address": 100.0,
        "Toe-up": 100.0,
        "Mid-backswing": 50.0,
        "Top": 100.0,
        "Mid-downswing": 100.0,
        "Impact": 50.0,
        "Mid-follow-through": 100.0,
        "Finish": 100.0,
    }
    assert card["per_event"] == expected_per_event
    assert card["per_event_correct"]["Mid-backswing"] == 1
    assert card["per_event_correct"]["Address"] == 2
    # Overall = (8 + 6) / 16 = 87.5%
    assert card["pce"] == 87.5
    assert card["n_correct"] == 14 and card["n_events"] == 16


def test_overall_pce_equals_mean_of_per_event_pce():
    # With a fixed 8 events per swing, the micro-average (overall) must equal
    # the macro-average over events.
    rng = np.random.default_rng(0)
    trues = np.array([TRUE + i for i in range(5)])
    preds = trues + rng.integers(-4, 5, size=trues.shape)
    card = score_dataset(preds, trues)
    mean_per_event = np.mean(list(card["per_event"].values()))
    assert abs(card["pce"] - mean_per_event) < 1e-9


def test_tolerance_scales_with_swing_length():
    # GolfDB derives tolerance from the address-to-impact span (a swing-length
    # proxy): tol = round(span / 30), floored at 1. Clean multiples of 30 have
    # no rounding ambiguity and show the linear scaling.
    for span, expected_tol in [(30, 1), (60, 2), (90, 3), (120, 4), (150, 5)]:
        ev = np.array([0, 5, 10, 15, 20, span, span + 10, span + 20])
        assert event_tolerance(ev) == expected_tol
    # Longer span => tolerance never shrinks.
    tols = [event_tolerance(np.array([0, 1, 2, 3, 4, s, s + 1, s + 2]))
            for s in range(0, 300, 5)]
    assert tols == sorted(tols)


def test_tolerance_rounding_and_floor_are_faithful():
    # Exactly matches int(max(np.round(span/30), 1)), incl. numpy's round-half-
    # to-even and the minimum-of-1 floor.
    cases = {
        0: 1,     # round(0.0)=0 -> floored to 1
        10: 1,    # round(0.333)=0 -> floored to 1
        15: 1,    # round(0.5)=0 (half to even) -> floored to 1
        29: 1,    # round(0.966)=1
        45: 2,    # round(1.5)=2 (half to even)
        75: 2,    # round(2.5)=2 (half to even)
        90: 3,    # round(3.0)=3
    }
    for span, expected in cases.items():
        ev = np.array([0, 1, 2, 3, 4, span, span + 1, span + 2])
        assert event_tolerance(ev) == expected
        # cross-check against the literal reference expression
        assert event_tolerance(ev) == int(max(np.round(span / 30), 1))


def test_explicit_tol_override():
    # A caller-supplied tolerance bypasses the GolfDB formula for every event.
    preds = TRUE + 5  # every event off by exactly 5 frames
    assert not score_swing(preds, TRUE).any()          # default tol=2 -> all wrong
    assert not score_swing(preds, TRUE, tol=4).any()   # tol=4 (<5) -> still all wrong
    assert score_swing(preds, TRUE, tol=5).all()       # tol=5 (>=5) -> all correct


def test_events_from_probs_matches_argmax_and_is_model_agnostic():
    # Build a (seq_length, 9) probability array whose per-class argmax sits at
    # the known TRUE frames, then confirm we recover TRUE and can score it.
    seq_length = 130
    probs = np.full((seq_length, N_EVENTS + 1), 0.01)
    for i, frame in enumerate(TRUE):
        probs[frame, i] = 0.99
    recovered = events_from_probs(probs)
    assert list(recovered) == list(TRUE)

    # The recovered frames feed the exact same scorer a frontier model would use.
    card = score_dataset([recovered], [TRUE], seq_lengths=[seq_length])
    assert card["pce"] == 100.0


def test_score_swing_validates_shape_and_range():
    # Must supply exactly 8 predicted and 8 true events.
    _raises(ValueError, lambda: score_swing(TRUE[:7], TRUE))
    _raises(ValueError, lambda: score_swing(TRUE, TRUE[:7]))
    # seq_length (when given) validates that ground-truth frames are in range.
    _raises(ValueError, lambda: score_swing(TRUE, TRUE, seq_length=60))
    # In-range is fine.
    assert score_swing(TRUE, TRUE, seq_length=121).all()


def test_score_dataset_uses_per_swing_tolerance():
    # Two swings with very different spans must be judged with different tols.
    short = np.array([0, 3, 6, 9, 12, 30, 40, 50])    # span 30 -> tol 1
    long_ = np.array([0, 20, 40, 60, 80, 120, 160, 200])  # span 120 -> tol 4
    trues = np.array([short, long_])
    # Offset every event by 3 frames: wrong for the short swing (tol 1),
    # correct for the long swing (tol 4).
    preds = trues + 3
    card = score_dataset(preds, trues)
    assert list(card["tolerances"]) == [1, 4]
    assert not card["correct"][0].any()   # short swing: all wrong
    assert card["correct"][1].all()       # long swing: all correct
    assert card["pce"] == 50.0


def test_format_scorecard_is_readable():
    card = score_dataset([TRUE], [TRUE])
    text = format_scorecard(card)
    assert "Overall PCE: 100.00%" in text
    for name in EVENTS:
        assert name in text


def _raises(exc, fn):
    """Tiny assert helper: fn() must raise exc."""
    try:
        fn()
    except exc:
        return
    raise AssertionError("expected {} to be raised".format(exc.__name__))


def _run():
    """Standalone runner: execute every test_* function, report pass/fail."""
    tests = [
        (name, obj)
        for name, obj in sorted(globals().items())
        if name.startswith("test_") and callable(obj)
    ]
    passed, failed = 0, 0
    for name, fn in tests:
        try:
            fn()
        except Exception as exc:  # noqa: BLE001 - report every failure
            failed += 1
            print("FAIL  {}: {!r}".format(name, exc))
        else:
            passed += 1
            print("PASS  {}".format(name))
    print("\n{} passed, {} failed, {} total".format(passed, failed, passed + failed))
    return failed


if __name__ == "__main__":
    import sys

    sys.exit(1 if _run() > 0 else 0)
