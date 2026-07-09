"""End-to-end "analyze MY swing" — the app engine.

  video -> trained model finds the 8 events -> pose at Address/Top/Impact
        -> biomechanics faults -> "what's wrong"

Unlike scripts/fault_demo.py (which used GolfDB's labeled events), this uses the
TRAINED model to locate the events, so it works on ANY video — including your own.

Runs where torch + the trained checkpoint are: on Colab right after training
(models/swingnet_ours.pth.tar), or locally if you `pip install torch torchvision`
and download that checkpoint.

  python3 -m swing.analyze --video my_swing.mp4 --ckpt models/swingnet_ours.pth.tar
"""
from __future__ import annotations
import argparse, os, sys
import numpy as np, cv2
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from swing.eval import EVENTS
from swing.pose import pose_at_frames
from swing.biomechanics import analyze as analyze_faults, report


def _load_model(ckpt_path, device="cpu"):
    import torch, torch.nn as nn
    from torchvision.models import mobilenet_v2

    class EventDetector(nn.Module):
        def __init__(self):
            super().__init__()
            self.cnn = mobilenet_v2(weights=None).features
            self.rnn = nn.LSTM(1280, 256, 1, batch_first=True, bidirectional=True)
            self.lin = nn.Linear(512, 9)

        def forward(self, x):
            B, T, C, H, W = x.size()
            c = self.cnn(x.view(B * T, C, H, W)).mean(3).mean(2)
            r, _ = self.rnn(c.view(B, T, -1))
            return self.lin(r).view(B * T, 9)

    m = EventDetector().to(device)
    sd = __import__("torch").load(ckpt_path, map_location=device)
    m.load_state_dict(sd["model_state_dict"])
    m.eval()
    return m


def predict_events(video_path, ckpt_path, device="cpu"):
    """Return the predicted frame index of each of the 8 swing events."""
    import torch
    cap = cv2.VideoCapture(video_path)
    frames = []
    while True:
        ok, f = cap.read()
        if not ok:
            break
        frames.append(cv2.resize(cv2.cvtColor(f, cv2.COLOR_BGR2RGB), (160, 160)))
    cap.release()
    x = torch.as_tensor(np.asarray(frames)).float().permute(0, 3, 1, 2) / 255.0
    mean = torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1)
    std = torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1)
    x = (x - mean) / std
    m = _load_model(ckpt_path, device)
    probs = []
    with torch.no_grad():
        for j in range(0, len(x), 64):
            out = m(x[j:j + 64].unsqueeze(0).to(device))
            probs.append(torch.softmax(out, dim=1).cpu().numpy())
    probs = np.concatenate(probs)                      # (N_frames, 9)
    return [int(np.argmax(probs[:, i])) for i in range(8)]   # frame per event class


def analyze_swing(video_path, ckpt_path, device="cpu"):
    ev = predict_events(video_path, ckpt_path, device)
    A, T, I = ev[0], ev[3], ev[5]                       # Address, Top, Impact
    poses = pose_at_frames(video_path, [A, T, I])
    named = {k: v for k, v in {"Address": poses.get(A), "Top": poses.get(T),
                               "Impact": poses.get(I)}.items() if v}
    return {"events": dict(zip(EVENTS, ev)), "report": report(named)}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", required=True)
    ap.add_argument("--ckpt", default="models/swingnet_ours.pth.tar")
    a = ap.parse_args()
    out = analyze_swing(a.video, a.ckpt)
    print("Detected events (frame #):")
    for name, fr in out["events"].items():
        print(f"  {name:20s} frame {fr}")
    print("\n" + out["report"])
