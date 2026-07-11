"""Builds train/colab_club_detector.ipynb (valid JSON). Run: python3 scripts/build_club_notebook.py

Fine-tunes a small COCO-pretrained YOLO11n (detection) on a large golf-club dataset, then exports
the *in-memory just-trained model* to Core ML and downloads it — in ONE cell, with a class-count
assertion. This prevents the failure we hit where the export silently grabbed the 80-class COCO
base instead of the fine-tuned 3-class weights."""
import json
from pathlib import Path

C = []
def md(s): C.append(("markdown", s.strip("\n")))
def code(s): C.append(("code", s.strip("\n")))

md("""
# Golf Club Detector — fine-tune YOLO11n, export in one shot

Trains a **clubhead detector** for the swing-plane feature (clubhead box + hands → shaft → plane),
on a **6,750+ image** golf-club dataset. Same transfer-learning recipe as your swing model.

**Bulletproofed:** training and export are in **one cell** — it exports the *just-trained model
from memory* (so it can't accidentally export the untrained COCO base), **asserts it has the golf
classes (not 80)**, and downloads immediately. Run on an **L4** runtime so it finishes before a
disconnect. If it drops mid-train, just re-run that one cell.
""")

code("""
# 1) Install
%%capture
!pip install -q ultralytics roboflow coremltools
""")

md("""
### Setup
Free account at **roboflow.com** → **Settings → API Key** → paste below. Defaults target the
**6,750-image** `golf-club-tracking` dataset.
""")

code('''
# 2) Config
ROBOFLOW_API_KEY = ""                  # <- paste your free Roboflow API key
WORKSPACE = "club-head-tracking"
PROJECT   = "golf-club-tracking"
VERSION   = 2
FORMAT    = "yolov8"

BASE     = "yolo11n.pt"                # small COCO-pretrained detection base (80 classes -> we specialize to golf)
EPOCHS   = 40
IMGSZ    = 640
BATCH    = 16
PATIENCE = 15
assert ROBOFLOW_API_KEY, "Paste your Roboflow API key first."
''')

code('''
# 3) Download the dataset
from roboflow import Roboflow
rf = Roboflow(api_key=ROBOFLOW_API_KEY)
dataset = rf.workspace(WORKSPACE).project(PROJECT).version(VERSION).download(FORMAT)
DATA_YAML = dataset.location + "/data.yaml"
print(open(DATA_YAML).read())
import glob, os
for s in ["train", "valid", "test"]:
    p = os.path.join(dataset.location, s, "images")
    if os.path.isdir(p): print(f"{s}: {len(glob.glob(p + '/*'))} images")
''')

md("""
### 4) Train + export + download — ONE cell
Exports the model that's in memory right after training (guaranteed the fine-tuned weights), checks
it has the golf classes (not 80), and downloads the zip. **This is the cell that matters** — if the
runtime disconnects, re-run just this one.
""")

code('''
# 4) Fine-tune, then export the JUST-TRAINED model + download (can't grab the COCO base)
import shutil, os
from ultralytics import YOLO
model = YOLO(BASE)
model.train(data=DATA_YAML, epochs=EPOCHS, imgsz=IMGSZ, batch=BATCH, patience=PATIENCE, device=0, plots=True)

print("TRAINED CLASSES:", model.names)                 # expect the 3 golf classes, NOT 80 COCO names
assert len(model.names) <= 10, f"got {len(model.names)} classes — that's the base, not the golf model; re-check the dataset"

pkg = model.export(format="coreml", nms=True, imgsz=IMGSZ)   # export the in-memory trained model
zp = shutil.make_archive("club_detector_coreml", "zip", root_dir=os.path.dirname(pkg), base_dir=os.path.basename(pkg))
from google.colab import files; files.download(zp)
print("✅ downloaded club_detector_coreml.zip — exported straight from the trained model")
''')

code('''
# 5) (optional) Evaluate — club-head mAP (higher = better; v1 was ~0.02, our run hit 0.881)
metrics = model.val()
print("box mAP50:", round(float(metrics.box.map50), 3), "| mAP50-95:", round(float(metrics.box.map), 3))
for i, c in enumerate(metrics.box.ap_class_index):
    print(f"  class {c}  mAP50={metrics.box.ap50[i]:.3f}")
''')

code('''
# 6) (optional, last) Reality check on your own swing — upload via the Files panel, set CLIP
import os
CLIP = "/content/IMG_3927.MOV"
if os.path.exists(CLIP):
    model.predict(CLIP, save=True, conf=0.25, vid_stride=3)   # runs/detect/predict*/ ; watch the downswing
    print("done -> open runs/detect/predict*/ in the Files panel")
else:
    print("upload a down-the-line clip (folder icon -> Upload) and set CLIP to its path")
''')

md("""
## After it runs
The download is the **club_detector_coreml.zip** — send it to me and I'll confirm it's 3-class,
identify which class is the clubhead, and build the shaft → **swing plane → on-plane / over-the-top**
+ a down-the-line mode.

**Credit:** dataset Roboflow Universe (CC BY 4.0); base YOLO11n (Ultralytics, AGPL).
""")

nb = {"cells": [{"cell_type": k, "metadata": {}, "source": s.splitlines(keepends=True),
                 **({"outputs": [], "execution_count": None} if k == "code" else {})}
                for k, s in C],
      "metadata": {"accelerator": "GPU", "colab": {"provenance": []},
                   "kernelspec": {"display_name": "Python 3", "name": "python3"},
                   "language_info": {"name": "python"}},
      "nbformat": 4, "nbformat_minor": 5}
out = Path(__file__).resolve().parent.parent / "train" / "colab_club_detector.ipynb"
out.write_text(json.dumps(nb, indent=1))
print("wrote", out, "with", len(C), "cells")
