"""Demo: run the biomechanics fault layer on a REAL GolfDB clip at its labeled
events (Address / Top / Impact). Shows the "what's wrong with your swing" output
end-to-end — pose -> angles -> faults — WITHOUT needing the trained model (uses
ground-truth event frames). Face-on clips are best for sway/spine metrics.

  python3 scripts/fault_demo.py --view face --n 6
  python3 scripts/fault_demo.py --id 10
"""
from __future__ import annotations
import argparse, os, sys
import numpy as np, pandas as pd
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from swing.pose import pose_at_frames
from swing.biomechanics import analyze, report

PKL = os.path.join(ROOT, "data", "golfDB.pkl")
VIDDIR = os.path.join(ROOT, "data", "videos_160")


def run(clip_id=None, view="face", n=6):
    df = pd.read_pickle(PKL)
    rows = (df[df["id"] == clip_id] if clip_id is not None
            else df[df["view"].astype(str).str.contains(view, case=False)])
    shown = 0
    for _, row in rows.iterrows():
        ev = np.asarray(row["events"]); true8 = ev[1:9] - ev[0]
        A, T, I = int(true8[0]), int(true8[3]), int(true8[5])   # Address, Top, Impact
        path = os.path.join(VIDDIR, f"{row['id']}.mp4")
        if not os.path.exists(path):
            continue
        poses = pose_at_frames(path, [A, T, I])
        named = {k: v for k, v in {"Address": poses.get(A), "Top": poses.get(T),
                                   "Impact": poses.get(I)}.items() if v}
        print(f"\n=== clip {row['id']} | {row['view']} view | {row['club']} | "
              f"events A={A} T={T} I={I} ===")
        if len(named) < 2:
            print("  (pose not reliably detected at enough events — skipping)")
        else:
            faults = analyze(named)
            print("  detected at:", list(named))
            print("  " + report(named).replace("\n", "\n  "))
        shown += 1
        if n and shown >= n:
            break


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", type=int, default=None)
    ap.add_argument("--view", default="face")
    ap.add_argument("--n", type=int, default=6)
    a = ap.parse_args()
    run(a.id, a.view, a.n)
