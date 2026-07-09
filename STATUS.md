# STATUS — Swing Sequencer + Fault Analyzer

**One-liner:** a small specialized model that sequences a golf swing into its 8
events and flags biomechanical faults — something a frontier vision model can't do
from one video. Thesis/litmus/data/eval in [`SPEC.md`](SPEC.md).

## Result (the headline)
| System | PCE (val split 1) |
|---|--:|
| Frontier vision (gpt-5.4-mini) | **14.5%** |
| **Our small model (v1)** | **42.9%** |
| SwingNet paper (reference) | ~76% |

Same metric, same clips → our trained small model beats the frontier model **~3×** at
swing sequencing. Full numbers + why the paper hits ~76%: [`RESULTS.md`](RESULTS.md).

## What's here
- **Data:** GolfDB — 1,400 labeled swing clips + annotations (`data/golfDB.pkl`);
  clips fetched by the notebook (gitignored). Baseline code vendored in `vendor/`.
- **Eval (built first):** `swing/eval.py` — exact GolfDB PCE
  (`tol = round((Impact−Address)/30)`), 13 passing tests (`swing/tests/`).
- **Training:** `train/colab_swingnet.ipynb` — forks SwingNet (torchvision
  MobileNetV2 + BiLSTM), trains on GolfDB, prints PCE. **v1** (frozen backbone, T4)
  → 42.9%; **v2** (unfreeze + flip-aug + 2,500 iters, L4/A100) → targets ~76%.
- **Frontier litmus:** `swing/frontier_baseline.py` — feeds clip frames to a
  frontier vision model, scores with the *same* PCE → 14.5%.
- **Fault layer:** `swing/biomechanics.py` (sway / hip-slide / early-extension,
  computed from pose; 5 tests) + `swing/pose.py` (MediaPipe) +
  `scripts/fault_demo.py` (runs it on a real clip → "what's wrong").

## How to run
```bash
pip install -r requirements.txt
python3 -m swing.tests.test_eval             # eval self-tests (no data)
python3 -m swing.tests.test_biomechanics     # fault-layer self-tests
python3 scripts/fault_demo.py --view face --n 6   # faults on real clips (needs data + gateway creds not required)
python3 -m swing.frontier_baseline --k 25    # frontier litmus (needs gateway creds)
# training + PCE:  train/colab_swingnet.ipynb on Colab (L4/A100 for v2)
```

## Honest caveats
- **v1 = 42.9%**, not 76% — that gap is the reduced T4 recipe (frozen backbone,
  1000 iters, no aug), not model capacity. v2 closes it; run on L4/A100.
- **Fault thresholds are v1 / approximate** — a few pro swings get flagged for
  sway (the 0.4 shoulder-width cutoff is a touch tight, and 2D face-on conflates
  some weight-shift with head-slide). Mechanism is validated (tests + clean-vs-sway
  separation on real clips); calibrate ranges against a pro-swing baseline for v2.
- 2D single-view biomechanics (true 3D rotation needs depth/multi-view).

## Separate from the caddie project
The Commit-First caddie SLM lives in `../golf-slm` (its own repo). Independent.
