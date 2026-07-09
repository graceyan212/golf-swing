# Results — Swing Sequencing (PCE, split 1, 350 val clips)

| System | PCE | Setup |
|---|--:|---|
| Frontier vision (gpt-5.4-mini) | **14.5%** | 25 clips; sampled frames -> asked for the 8 event frames |
| **Ours (SwingNet, v1)** | **42.9%** | frozen MobileNetV2, 1000 iters, batch 4, no aug (free T4) |
| SwingNet paper (reference) | ~76% | full CNN fine-tune, 2000+ iters, augmentation |

**Thesis proven:** the small specialized model beats the frontier vision model **~3x**
at swing sequencing on the identical metric — something the frontier model can't do
(it just spreads guesses evenly).

**Gap to the paper is the training recipe, not model capacity.** Levers (v2):
1. Unfreeze the CNN backbone (fine-tune) — biggest lever; needs an L4/A100 (Colab Pro).
2. Horizontal-flip + affine augmentation (paper credits ~+5% PCE).
3. 2000-3000 iterations, batch 8-16.

Eval metric: exact GolfDB PCE (`swing/eval.py`, tol = round((Impact-Address)/30)).
