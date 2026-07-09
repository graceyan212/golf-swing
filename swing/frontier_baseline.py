"""Frontier-model litmus: can a frontier VISION model sequence a golf swing?

Feed sampled frames of a GolfDB clip to a frontier vision model (via the
TrueFoundry gateway), ask it for the 8 event frames, and score with the SAME PCE
metric our trained model uses. Expectation: far below SwingNet -> the headline
"small specialized model beats frontier at this narrow task."

  ANTHROPIC_BASE_URL=... ANTHROPIC_AUTH_TOKEN=... python3 -m swing.frontier_baseline --k 8
"""
from __future__ import annotations
import os, base64, json, argparse
import numpy as np, cv2, pandas as pd
from openai import OpenAI
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from swing.eval import EVENTS, score_swing, event_tolerance

HERE = os.path.dirname(os.path.abspath(__file__))
VIDDIR = os.path.join(HERE, "..", "data", "videos_160")
PKL = os.path.join(HERE, "..", "data", "golfDB.pkl")
VISION_MODEL = "gpt-5.4-mini"   # multimodal + reliable JSON via the gateway (frontier model)


def _client():
    return OpenAI(base_url=os.environ["ANTHROPIC_BASE_URL"].rstrip("/") + "/v1",
                  api_key=os.environ["ANTHROPIC_AUTH_TOKEN"], timeout=180)


def sample_frames(path, n=14):
    cap = cv2.VideoCapture(path)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    idxs = sorted(set(np.linspace(0, max(total - 1, 1), n).astype(int).tolist()))
    frames = {}
    for idx in idxs:
        cap.set(cv2.CAP_PROP_POS_FRAMES, int(idx))
        ok, img = cap.read()
        if ok:
            frames[int(idx)] = img
    cap.release()
    return total, frames


def _b64(img):
    ok, buf = cv2.imencode(".jpg", img)
    return base64.b64encode(buf.tobytes()).decode()


def ask_frontier(frames, total, model=VISION_MODEL):
    idxs = sorted(frames)
    content = [{"type": "text", "text":
        f"These are {len(idxs)} frames sampled in order from ONE golf swing video, each "
        f"labeled with its frame index (range 0..{total-1}). Identify the frame index of "
        f"each of the 8 swing events, which occur in this order: {', '.join(EVENTS)}. "
        f"Return ONLY a JSON object mapping each event name to an integer frame index "
        f'(e.g. {{"{EVENTS[0]}": 0, "{EVENTS[1]}": 5}}). Indices must be non-decreasing.'}]
    for idx in idxs:
        content.append({"type": "text", "text": f"frame {idx}:"})
        content.append({"type": "image_url",
                        "image_url": {"url": "data:image/jpeg;base64," + _b64(frames[idx])}})
    msgs = [{"role": "user", "content": content}]
    last = ""
    for attempt in range(3):
        r = _client().chat.completions.create(model=model, temperature=0,
                                              max_tokens=500 + attempt * 300, messages=msgs)
        txt = (r.choices[0].message.content or "").strip()
        last = txt
        if "{" in txt and "}" in txt:
            try:
                d = json.loads(txt[txt.find("{"): txt.rfind("}") + 1])
                return [int(round(float(d[e]))) for e in EVENTS]
            except (json.JSONDecodeError, KeyError, ValueError, TypeError):
                pass
    raise ValueError(f"no parseable JSON (last={last[:80]!r})")


def run(split=1, k=8, model=VISION_MODEL):
    df = pd.read_pickle(PKL)
    val = df[df["split"] == split].head(k)
    print(f"[frontier] {model} on {len(val)} clips (val split {split})", flush=True)
    per_clip = []
    for _, row in val.iterrows():
        ev = np.asarray(row["events"])
        true8 = (ev[1:9] - ev[0]).tolist()
        path = os.path.join(VIDDIR, f"{row['id']}.mp4")
        if not os.path.exists(path):
            continue
        total, frames = sample_frames(path)
        try:
            pred8 = ask_frontier(frames, total, model)
            pred8 = [min(max(p, 0), total - 1) for p in pred8]
            correct = np.asarray(score_swing(pred8, true8), dtype=float)
        except Exception as e:
            print(f"  clip {row['id']}: ERROR {type(e).__name__}: {str(e)[:80]}", flush=True)
            continue
        per_clip.append(correct)
        print(f"  clip {row['id']}: {int(correct.mean()*100):3d}%  tol={event_tolerance(true8)}  "
              f"pred={pred8} true={true8}", flush=True)
    if per_clip:
        pce = float(np.mean(np.concatenate(per_clip)))
        print(f"\nFRONTIER PCE ({model}, {len(per_clip)} clips): {pce*100:.1f}%  "
              f"(SwingNet ~76%)", flush=True)
        return pce
    print("no clips scored", flush=True)
    return 0.0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--split", type=int, default=1)
    ap.add_argument("--k", type=int, default=8)
    ap.add_argument("--model", default=VISION_MODEL)
    a = ap.parse_args()
    run(a.split, a.k, a.model)
