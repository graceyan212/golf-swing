# golf-swing — Swing Sequencer + Fault Analyzer

A **small specialized model** that does what a frontier model can't: take one golf
swing video, **sequence it into its 8 events** frame-accurately, and **flag specific
faults** from measured biomechanics. Thesis, litmus, data, and eval in
[`SPEC.md`](SPEC.md).

> Separate from the caddie project — that lives in `../golf-slm` (preserved locally
> + on GitHub). This is its own repo.

## Why it beats a frontier model
A frontier vision model has no biomechanical representation of a swing, so from one
video it gives generic advice. A model trained on **pose sequences** (GolfDB) learns
the actual motion — frame-accurate events + measurable angles it can't produce.

## Repo map
```
SPEC.md              thesis / litmus / data / eval / process
data/                GolfDB acquisition (see data/README.md); poses/ (gitignored)
swing/
  pose.py            per-frame pose extraction (MediaPipe/HRNet) -> keypoint sequences
  sequencing/        the event detector (fork of SwingNet; alt pose->temporal model)
  biomechanics.py    angles at each event -> fault flags (the "what's wrong" layer)
  eval.py            PCE metric + per-event breakdown + frontier-baseline comparison
train/
  colab_swingnet.ipynb   train the event detector on GolfDB (Colab GPU)
scripts/
```

## Pipeline
```
video ─► pose (off-the-shelf) ─► [TRAINED] event detector ─► 8 event frames
                                        │
                                        ▼
                              [COMPUTED] biomechanics at each event ─► fault flags
```

## Quickstart (planned)
```bash
pip install -r requirements.txt
# 1) get GolfDB (annotations + preprocessed clips) — see data/README.md
# 2) extract pose sequences
python -m swing.pose --split data/golfDB.pkl
# 3) train the event detector (Colab GPU) — train/colab_swingnet.ipynb
# 4) eval: PCE vs GolfDB labels + frontier comparison
python -m swing.eval --checkpoint models/swingnet.pt
```

## Status
Scaffolded. Next: GolfDB acquisition + pose extraction → train the event detector →
PCE eval + frontier baseline → biomechanics fault layer → demo on own swings.
