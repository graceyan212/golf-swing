# Swing Sequencer + Fault Analyzer — Spec

**One-line thesis (the litmus):** hand a frontier model *one swing video* and it gives
platitudes ("stay balanced"). A **small specialized model trained on pose-sequence
data** can (1) sequence the swing into its 8 events frame-accurately and (2) measure
the biomechanics at each event to flag a *specific* fault. Frontier vision models
lack a **biomechanical motion representation** — that's the gap (the same "the
default tokenization/representation is wrong for this modality" idea as the
instructor-highlighted music project).

## What the system does (falsifiable)
- **Input:** a single-view golf swing video (face-on or down-the-line).
- **Output A — trained model:** the 8 swing **event** frames — Address, Toe-up,
  Mid-backswing, Top, Mid-downswing, Impact, Mid-follow-through, Finish.
- **Output B — computed on top:** at key events, measured biomechanics from pose
  (shoulder turn, hip turn, X-factor at Top; spine angle, hip-slide/early-extension
  at Impact; arm/club line for over-the-top) → flagged **faults** where they fall
  outside good ranges.

A stranger can mark it: are the 8 event frames within tolerance of the labels
(PCE)? Are the flagged faults consistent with the measured angles?

## Data
- **GolfDB** (McNally et al., arXiv 1903.06528; code github.com/wmcnally/GolfDB) —
  **1,400 labeled swing videos**, 8 event frames each + club/view/player metadata.
  This is the training + eval corpus ("everyone's data").
- **Pose** extracted per frame via MediaPipe/HRNet (an off-the-shelf model — we do
  NOT train pose estimation).
- **User's own swing videos** — the demo + a personal test set ("my data").

**Honest data note:** GolfDB labels are swing **events (phases), not faults.** No
public dataset has expert fault labels. So the **trained** part is event
sequencing; the **fault** layer is *computed* from pose geometry (deviation from
good ranges), the same "derive the ground truth from math" approach the field uses.

## Eval (built with training, not after)
1. **Event detection — PCE** (Percent of Correct Events within a frame tolerance),
   the GolfDB benchmark. Baseline to beat/match: SwingNet ≈ 76% PCE. Report per-event
   (Address/Finish are known-hardest).
2. **Fault layer** — validate computed angles against known-good ranges + sanity on
   labeled pro swings; qualitative on the user's swing.
3. **Frontier baseline (the litmus, mirrors base-vs-tuned):** give GPT/Gemini the
   same video and ask for the 8 events + faults → show it can't produce
   frame-accurate events or measured faults. Our small model vs frontier is the
   headline result.

## Process (the graded emphasis)
GolfDB → pose sequences → train/val split → small temporal model (fork SwingNet;
alt: pose→1D-CNN/LSTM) → PCE eval + frontier comparison → iterate on the weakest
events → add the biomechanics fault layer → demo on the user's swing.

## Scope / non-goals
- Not training pose estimation (use off-the-shelf).
- Not full 3D biomechanics or club tracking (2D pose + key angles is enough for v1).
- Not a trained fault classifier in v1 (no fault labels) — faults are computed;
  hand-labeling a small fault set is a stretch goal.
- Separate from the caddie project (that lives in ../golf-slm, preserved).
