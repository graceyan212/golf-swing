"""Builds train/colab_swingnet.ipynb (valid JSON). Run: python3 scripts/build_train_notebook.py"""
import json
from pathlib import Path

C = []
def md(s): C.append(("markdown", s.strip("\n")))
def code(s): C.append(("code", s.strip("\n")))

md("""
# Swing Sequencer — train SwingNet on GolfDB (Colab GPU)

Forks the SwingNet baseline (MobileNetV2 CNN + BiLSTM → 8 swing events) and trains it
on GolfDB (1,400 clips), then reports **PCE** (Percent of Correct Events). One
robustness change vs the original repo: the CNN backbone uses **torchvision's**
pretrained MobileNetV2 (no fragile extra weights file).

Runtime: **T4 GPU**. Data is pulled straight into Colab via gdown (fast). ~20–40 min.
""")

code("""
# 1) Install
%%capture
!pip install -q torch torchvision opencv-python-headless scipy pandas gdown tqdm
""")

code("""
# 2) Get the GolfDB code (model/dataloader/eval/util + golfDB.mat) + the video clips
%cd /content
!rm -rf GolfDB && git clone -q https://github.com/wmcnally/GolfDB
%cd /content/GolfDB
# videos_160 (~667MB) straight from the dataset's Google Drive
!gdown -q 1uBwRxFxW04EqG87VCoX3l6vXeV5T5JYJ -O data/videos_160.zip
!cd data && unzip -o -q videos_160.zip && ls videos_160 | wc -l
# convert the .mat annotations -> dataframe + the 4 cross-val splits
!python generate_splits.py
!ls data/*.pkl
""")

code("""
# 3) Config
import torch, os
DEVICE = 'cuda' if torch.cuda.is_available() else 'cpu'
SPLIT       = 1
SEQ_LENGTH  = 64
BATCH       = 6          # T4-friendly (original used 22 on a bigger GPU)
ITERATIONS  = 1000       # bump for a better model; 1000 is a solid first run
LR          = 1e-3
print("device:", DEVICE)
""")

code('''
# 4) Model — SwingNet EventDetector with a torchvision MobileNetV2 backbone
import torch.nn as nn
from torchvision.models import mobilenet_v2, MobileNet_V2_Weights

class EventDetector(nn.Module):
    def __init__(self, lstm_layers=1, lstm_hidden=256, bidirectional=True, dropout=False, pretrained=True):
        super().__init__()
        w = MobileNet_V2_Weights.IMAGENET1K_V1 if pretrained else None
        self.cnn = mobilenet_v2(weights=w).features          # -> (B,1280,H,W)
        self.rnn = nn.LSTM(1280, lstm_hidden, lstm_layers,
                           batch_first=True, bidirectional=bidirectional)
        self.lin = nn.Linear((2 if bidirectional else 1)*lstm_hidden, 9)  # 8 events + no-event
        self.dropout = dropout
        if dropout: self.drop = nn.Dropout(0.5)
    def forward(self, x):
        B, T, Ch, H, W = x.size()
        c = self.cnn(x.view(B*T, Ch, H, W)).mean(3).mean(2)  # global avg pool
        if self.dropout: c = self.drop(c)
        r, _ = self.rnn(c.view(B, T, -1))
        return self.lin(r).view(B*T, 9)

model = EventDetector(pretrained=True).to(DEVICE)
print(sum(p.numel() for p in model.parameters())/1e6, "M params")
''')

code("""
# 5) Data (reuse the repo's GolfDB dataset + transforms)
from dataloader import GolfDB, Normalize, ToTensor
from torch.utils.data import DataLoader
from torchvision import transforms

train_ds = GolfDB(data_file=f'data/train_split_{SPLIT}.pkl', vid_dir='data/videos_160/',
                  seq_length=SEQ_LENGTH,
                  transform=transforms.Compose([ToTensor(),
                      Normalize([0.485,0.456,0.406],[0.229,0.224,0.225])]),
                  train=True)
train_dl = DataLoader(train_ds, batch_size=BATCH, shuffle=True, num_workers=2, drop_last=True)
print("train clips:", len(train_ds))
""")

code("""
# 6) Train (weighted CE — events are ~1:35 vs no-event)
weights = torch.FloatTensor([1/8]*8 + [1/35]).to(DEVICE)
criterion = torch.nn.CrossEntropyLoss(weight=weights)
optimizer = torch.optim.Adam(model.parameters(), lr=LR)
model.train()
i, done = 0, False
while not done:
    for sample in train_dl:
        images = sample['images'].to(DEVICE)
        labels = sample['labels'].to(DEVICE).view(BATCH*SEQ_LENGTH)
        logits = model(images)
        loss = criterion(logits, labels)
        optimizer.zero_grad(); loss.backward(); optimizer.step()
        if i % 20 == 0: print(f"it {i:4d}  loss {loss.item():.4f}")
        i += 1
        if i >= ITERATIONS: done = True; break
os.makedirs('models', exist_ok=True)
torch.save({'model_state_dict': model.state_dict()}, 'models/swingnet_ours.pth.tar')
print("saved models/swingnet_ours.pth.tar")
""")

code("""
# 7) Eval — PCE on the val split (exact GolfDB metric via util.correct_preds)
import numpy as np
from dataloader import GolfDB
from util import correct_preds
from torch.nn.functional import softmax

val_ds = GolfDB(data_file=f'data/val_split_{SPLIT}.pkl', vid_dir='data/videos_160/',
                seq_length=SEQ_LENGTH,
                transform=transforms.Compose([ToTensor(),
                    Normalize([0.485,0.456,0.406],[0.229,0.224,0.225])]),
                train=False)
model.eval()
correct = []
with torch.no_grad():
    for i in range(len(val_ds)):
        s = val_ds[i]
        imgs = s['images']            # (T,C,H,W)
        # batch the clip through the CNN+LSTM in chunks to fit memory
        probs = []
        B = 64
        for j in range(0, imgs.shape[0], B):
            batch = torch.as_tensor(imgs[j:j+B]).unsqueeze(0).to(DEVICE)
            out = model(batch)
            probs.append(softmax(out, dim=1).cpu().numpy())
        probs = np.concatenate(probs)
        _, _, _, c = correct_preds(probs, s['labels'])
        correct.append(c)
        if i % 50 == 0: print(f"eval {i}/{len(val_ds)}")
PCE = float(np.mean(np.concatenate(correct))) if len(correct) else 0.0
print(f"\\nVAL PCE (split {SPLIT}): {PCE*100:.1f}%  (SwingNet paper baseline ~76%)")
""")

md("""
## Read the result
PCE = fraction of the 8 swing events detected within tolerance. Baseline SwingNet is
~76% on split 1. Next in the repo: the **frontier-baseline litmus** (feed a clip to
GPT/Gemini vision, score with the *same* PCE — it can't sequence a swing), and the
**biomechanics fault layer** (angles at each detected event → what's wrong).
Fixes/version nits are expected on first Colab run — send the error and iterate.
""")

nb = {"cells": [{"cell_type": k, "metadata": {}, "source": s.splitlines(keepends=True),
                 **({"outputs": [], "execution_count": None} if k == "code" else {})}
                for k, s in C],
      "metadata": {"accelerator": "GPU", "colab": {"provenance": []},
                   "kernelspec": {"display_name": "Python 3", "name": "python3"},
                   "language_info": {"name": "python"}},
      "nbformat": 4, "nbformat_minor": 5}
out = Path(__file__).resolve().parent.parent / "train" / "colab_swingnet.ipynb"
out.write_text(json.dumps(nb, indent=1))
print("wrote", out, "with", len(C), "cells")
