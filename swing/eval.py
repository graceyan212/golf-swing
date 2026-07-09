"""PCE (Percentage of Correct Events) — the GolfDB swing-sequencing metric.

This is the benchmark metric from GolfDB (McNally et al., *GolfDB: A Video
Database for Golf Swing Sequencing*, arXiv:1903.06528; code at
https://github.com/wmcnally/GolfDB). We replicate it faithfully so our small
trained model and a frontier-model baseline can be scored identically — the
"litmus" comparison in ``SPEC.md``.

The metric in one line: a predicted event frame is **correct** when it lands
within a frame *tolerance* of the ground-truth frame, and PCE is the percentage
of events that are correct.

The tolerance is not a fixed number of frames — it scales with the swing. The
reference implementation (``vendor/GolfDB/util.py::correct_preds``) computes it
per swing as::

    tol = int(max(np.round((events[5] - events[0]) / 30), 1))
    correct = (np.abs(events - preds) <= tol)

where ``events`` are the 8 ground-truth event frames in chronological order, so
``events[0]`` is Address and ``events[5]`` is Impact. In other words the
tolerance is ~1/30 of the *address-to-impact* frame span (a proxy for how long,
in frames, the swing takes), floored at 1 frame. A faster/shorter swing (or a
lower-frame-rate clip) yields a tighter tolerance; a slower/longer one yields a
looser tolerance. GolfDB's own docstring: "tolerance based on number of frames
from address to impact."

Design notes
------------
* **numpy only** — no torch, no dataset, no GPU. This is pure metric logic.
* **Model-agnostic** — everything here operates on *event frame indices*
  (8 integers per swing). Where those integers come from is irrelevant: our
  trained detector produces them via argmax over its per-frame class
  probabilities (see :func:`events_from_probs`), while a frontier model can be
  asked to simply name the 8 frames. Both are scored by the exact same code.
* GolfDB returns PCE as a fraction in ``[0, 1]`` (``np.mean(correct)``); we
  report it as a percentage in ``[0, 100]`` to match the paper and ``SPEC.md``.
"""

import numpy as np

# The 8 swing events, in chronological order. These are GolfDB event classes
# 0..7 (class 8 is the "no-event" frame class, not scored). Order matters: the
# tolerance formula indexes Address (0) and Impact (5).
EVENTS = [
    "Address",
    "Toe-up",
    "Mid-backswing",
    "Top",
    "Mid-downswing",
    "Impact",
    "Mid-follow-through",
    "Finish",
]

N_EVENTS = len(EVENTS)  # 8

# GolfDB divides the address-to-impact span by this constant to size the
# tolerance, and floors the result at this minimum (see module docstring).
TOL_DIVISOR = 30
TOL_MIN = 1

# Positions of Address and Impact within an ordered event vector — the two
# frames the tolerance formula depends on.
ADDRESS_IDX = 0
IMPACT_IDX = 5


def event_tolerance(true_events):
    """Frame tolerance for one swing, exactly as GolfDB defines it.

    Replicates ``vendor/GolfDB/util.py::correct_preds``::

        tol = int(max(np.round((events[5] - events[0]) / 30), 1))

    :param true_events: ground-truth event frame indices, ordered
        chronologically, shape (8,). Only Address (index 0) and Impact
        (index 5) are used.
    :return: tolerance in frames (int), always >= ``TOL_MIN`` (1).
    """
    true_events = np.asarray(true_events)
    span = true_events[IMPACT_IDX] - true_events[ADDRESS_IDX]
    return int(max(np.round(span / TOL_DIVISOR), TOL_MIN))


def score_swing(pred_events, true_events, seq_length=None, tol=None):
    """Score ONE swing: which of the 8 events were predicted within tolerance.

    A predicted event frame ``p`` is correct iff ``|p - t| <= tol`` against its
    ground-truth frame ``t`` (GolfDB uses ``<=``, so the tolerance boundary
    counts as correct). ``tol`` defaults to the GolfDB per-swing tolerance
    (:func:`event_tolerance`).

    Model-agnostic: ``pred_events`` is just 8 integer frame indices from *any*
    source. A prediction that is missing or refused (e.g. a frontier model that
    would not commit to a frame) should be passed as a deliberately out-of-range
    sentinel so it scores as incorrect — the metric is defined over all 8
    events and this function requires exactly 8 predictions.

    :param pred_events: predicted event frame indices, shape (8,).
    :param true_events: ground-truth event frame indices (chronological),
        shape (8,).
    :param seq_length: total number of frames in the clip. Optional; when
        given it is used only to validate that the ground-truth frames are in
        range ``[0, seq_length)``. The tolerance itself is derived from the
        address-to-impact span, not the clip length (per GolfDB).
    :param tol: explicit tolerance override in frames. Default ``None`` uses
        the GolfDB tolerance.
    :return: boolean ``np.ndarray`` of shape (8,); ``correct[i]`` is whether
        ``EVENTS[i]`` was predicted within tolerance.
    """
    pred_events = np.asarray(pred_events, dtype=float)
    true_events = np.asarray(true_events, dtype=float)

    if pred_events.shape != (N_EVENTS,) or true_events.shape != (N_EVENTS,):
        raise ValueError(
            "expected exactly {n} predicted and {n} true event frames, got "
            "pred={p}, true={t} (pad missing predictions with an out-of-range "
            "sentinel so they score as incorrect)".format(
                n=N_EVENTS, p=pred_events.shape, t=true_events.shape
            )
        )
    if seq_length is not None:
        if not np.all((true_events >= 0) & (true_events < seq_length)):
            raise ValueError(
                "true event frames {t} out of range for seq_length={s}".format(
                    t=true_events.tolist(), s=seq_length
                )
            )

    if tol is None:
        tol = event_tolerance(true_events)

    deltas = np.abs(true_events - pred_events)
    return deltas <= tol


def events_from_probs(probs):
    """Convert a detector's per-frame class probabilities to 8 event frames.

    Bridges GolfDB-style model output to the frame-index interface used by the
    rest of this module. Faithful to ``correct_preds``: for each event class
    ``i`` the predicted frame is the frame that maximises that class's
    probability (``np.argsort(probs[:, i])[-1]``).

    :param probs: array of shape (seq_length, C) with C >= 8. Column ``i`` is
        the probability of event class ``i`` at each frame. GolfDB uses C = 9
        (8 events + a no-event class); only the first 8 columns are read.
    :return: predicted event frame indices, shape (8,), dtype int.
    """
    probs = np.asarray(probs)
    if probs.ndim != 2 or probs.shape[1] < N_EVENTS:
        raise ValueError(
            "probs must be (seq_length, C>={n}), got {s}".format(
                n=N_EVENTS, s=probs.shape
            )
        )
    preds = np.array(
        [np.argsort(probs[:, i])[-1] for i in range(N_EVENTS)], dtype=int
    )
    return preds


def score_dataset(preds, trues, seq_lengths=None, tol=None):
    """Aggregate PCE over a dataset of swings into a scorecard.

    Each swing is scored independently with its own GolfDB tolerance, then
    results are pooled. Overall PCE is the percentage of correct events across
    *all* events of all swings (``np.mean`` over the full correctness matrix,
    matching GolfDB, scaled to a percentage). Because every swing contributes
    exactly 8 events, this micro-average equals the mean of the per-event PCEs.

    :param preds: predicted event frames for N swings, array-like of shape
        (N, 8). Assemble this from any source (see :func:`events_from_probs`
        for the trained-model path).
    :param trues: ground-truth event frames, array-like of shape (N, 8).
    :param seq_lengths: optional per-swing clip lengths, shape (N,), used only
        for range validation of the ground truth.
    :param tol: explicit tolerance override applied to every swing. Default
        ``None`` uses each swing's GolfDB tolerance.
    :return: scorecard dict with keys:
        ``pce`` (float %), ``per_event`` ({name: %}),
        ``per_event_correct`` ({name: int}), ``per_event_total`` (int),
        ``n_swings`` (int), ``n_correct`` (int), ``n_events`` (int),
        ``correct`` (bool ndarray (N, 8)), ``tolerances`` (int ndarray (N,)).
    """
    preds = np.asarray(preds, dtype=float)
    trues = np.asarray(trues, dtype=float)
    if preds.ndim != 2 or preds.shape[1] != N_EVENTS:
        raise ValueError("preds must be (N, {n}), got {s}".format(n=N_EVENTS, s=preds.shape))
    if preds.shape != trues.shape:
        raise ValueError(
            "preds {p} and trues {t} must have the same shape".format(
                p=preds.shape, t=trues.shape
            )
        )
    n_swings = preds.shape[0]

    correct = np.zeros((n_swings, N_EVENTS), dtype=bool)
    tolerances = np.zeros(n_swings, dtype=int)
    for i in range(n_swings):
        seq_length = None if seq_lengths is None else int(seq_lengths[i])
        correct[i] = score_swing(preds[i], trues[i], seq_length=seq_length, tol=tol)
        tolerances[i] = tol if tol is not None else event_tolerance(trues[i])

    # np.mean over the whole matrix == GolfDB's np.mean(correct), as a percent.
    pce = 100.0 * correct.mean() if n_swings else 0.0
    per_event_rate = correct.mean(axis=0) if n_swings else np.zeros(N_EVENTS)

    return {
        "pce": pce,
        "per_event": {name: 100.0 * r for name, r in zip(EVENTS, per_event_rate)},
        "per_event_correct": {
            name: int(c) for name, c in zip(EVENTS, correct.sum(axis=0))
        },
        "per_event_total": n_swings,
        "n_swings": n_swings,
        "n_correct": int(correct.sum()),
        "n_events": int(correct.size),
        "correct": correct,
        "tolerances": tolerances,
    }


def format_scorecard(scorecard, title="Swing Sequencing — PCE"):
    """Render a scorecard (from :func:`score_dataset`) as a printable table.

    :param scorecard: dict returned by :func:`score_dataset`.
    :param title: heading for the report.
    :return: multi-line string with overall PCE and a per-event breakdown.
    """
    lines = []
    lines.append(title)
    lines.append("=" * len(title))
    lines.append(
        "Overall PCE: {pce:6.2f}%   ({nc}/{ne} events over {ns} swings)".format(
            pce=scorecard["pce"],
            nc=scorecard["n_correct"],
            ne=scorecard["n_events"],
            ns=scorecard["n_swings"],
        )
    )
    lines.append("")
    name_w = max(len(e) for e in EVENTS)
    header = "{name:<{w}}   {pce:>7}   {frac:>9}".format(
        name="Event", w=name_w, pce="PCE", frac="correct"
    )
    lines.append(header)
    lines.append("-" * len(header))
    total = scorecard["per_event_total"]
    for name in EVENTS:
        lines.append(
            "{name:<{w}}   {pce:6.2f}%   {c:>4}/{t:<4}".format(
                name=name,
                w=name_w,
                pce=scorecard["per_event"][name],
                c=scorecard["per_event_correct"][name],
                t=total,
            )
        )
    return "\n".join(lines)


def print_scorecard(scorecard, title="Swing Sequencing — PCE"):
    """Print the formatted scorecard (see :func:`format_scorecard`)."""
    print(format_scorecard(scorecard, title=title))


if __name__ == "__main__":
    # No-data self-demo: score a couple of synthetic swings so `python -m
    # swing.eval` shows a scorecard without needing a model or dataset.
    demo_trues = np.array(
        [
            [0, 12, 24, 36, 48, 60, 90, 120],
            [0, 12, 24, 36, 48, 60, 90, 120],
        ]
    )
    demo_preds = np.array(
        [
            [0, 12, 24, 36, 48, 60, 90, 120],   # perfect swing
            [0, 14, 21, 37, 50, 63, 90, 120],   # a few events off (tol = 2)
        ]
    )
    print_scorecard(score_dataset(demo_preds, demo_trues))
