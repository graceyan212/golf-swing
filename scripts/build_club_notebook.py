"""Builds train/colab_club_detector.ipynb (valid JSON). Run: python3 scripts/build_club_notebook.py

Fine-tunes a small COCO-pretrained YOLO11n (detection) on a large golf-club dataset so it locates
the club head. Clubhead box + hands (from Vision) -> shaft -> swing plane.

Hardened after repeated Colab disconnects: the moment training finishes it SAVES the model to
Google Drive AND downloads the Core ML zip, before eval/video steps — so a disconnect can't cost
you the trained model. The video reality-check runs last and lightweight (it's what was crashing
the runtime)."""
import json
from pathlib import Path

C = []
def md(s): C.append(("markdown", s.strip("\n")))
def code(s): C.append(("code", s.strip("\n")))

md("""
# Golf Club Detector — fine-tune YOLO11n (detection), disconnect-proof

Trains a **clubhead detector** for the swing-plane feature. Same transfer-learning recipe as your
swing model (small COCO-pretrained base → fine-tune on task data), on a **6,750+ image** golf-club
dataset.

**Hardened against Colab disconnects:** as soon as training finishes, the notebook **saves the
model to your Google Drive and downloads it** — *before* anything that could drop the runtime. The
video test (which was crashing the session on big clips) runs **last** and only every 3rd frame.

Order: install → data → **train → SAVE+DOWNLOAD** → eval → (optional) video test.
""")

code("""
# 1) Install
%%capture
!pip install -q ultralytics roboflow coremltools
""")

md("""
### One-time setup
1. Free account at **roboflow.com** → **Settings → API Key** → paste into `ROBOFLOW_API_KEY`.
2. When cell 5 runs it will **ask for Google Drive permission** — click through; that's how it
   parks a durable copy of your model so a disconnect never loses it.
""")

code('''
# 2) Config
ROBOFLOW_API_KEY = ""                  # <- paste your free Roboflow API key
WORKSPACE = "club-head-tracking"       # 6,750-image golf-club-tracking dataset
PROJECT   = "golf-club-tracking"
VERSION   = 2
FORMAT    = "yolov8"                   # detection format (trains fine with YOLO11)

BASE     = "yolo11n.pt"                # small COCO-pretrained DETECTION base (phone-friendly)
EPOCHS   = 40
IMGSZ    = 640
BATCH    = 16
PATIENCE = 15                          # early-stop if it stops improving (saves Colab time)
WEIGHTS  = "/content/runs/detect/train/weights/best.pt"
assert ROBOFLOW_API_KEY, "Paste your Roboflow API key first."
''')

code('''
# 3) Download the dataset (or paste Roboflow's exact snippet if these slugs error)
from roboflow import Roboflow
rf = Roboflow(api_key=ROBOFLOW_API_KEY)
version = rf.workspace(WORKSPACE).project(PROJECT).version(VERSION)
dataset = version.download(FORMAT)
DATA_YAML = dataset.location + "/data.yaml"
print("dataset at:", dataset.location)
print(open(DATA_YAML).read())
import glob, os
for s in ["train", "valid", "test"]:
    p = os.path.join(dataset.location, s, "images")
    if os.path.isdir(p): print(f"{s}: {len(glob.glob(p + '/*'))} images")   # should be THOUSANDS
''')

code('''
# 4) Fine-tune (COCO-pretrained base -> specialize on golf clubs)
from ultralytics import YOLO
model = YOLO(BASE)
model.train(data=DATA_YAML, epochs=EPOCHS, imgsz=IMGSZ, batch=BATCH, patience=PATIENCE,
            device=0, plots=True)
print("best weights:", model.trainer.best)
''')

md("""
### 5) 🔒 Secure the model NOW — runs the instant training ends
Saves `best.pt` to **Drive** (durable) and **downloads** the Core ML zip. It reloads from the
weights file, so it works even if a reconnect wiped your Python variables. **Approve the Drive
prompt when it appears.**
""")

code('''
# 5) Save to Drive + download Core ML — before anything can disconnect you
import shutil, os
from ultralytics import YOLO
assert os.path.exists(WEIGHTS), "best.pt missing — training didn't finish; re-run cell 4."
# a) durable copy to Google Drive first (small + fast; survives any disconnect)
try:
    from google.colab import drive; drive.mount("/content/drive")
    os.makedirs("/content/drive/MyDrive/golf", exist_ok=True)
    shutil.copy(WEIGHTS, "/content/drive/MyDrive/golf/club_best.pt")
    print("✅ weights parked in Drive: MyDrive/golf/club_best.pt")
except Exception as e:
    print("Drive save skipped (", e, ") — still downloading below.")
# b) export Core ML, zip (so the folder actually downloads), and pull to your computer
pkg = YOLO(WEIGHTS).export(format="coreml", nms=True, imgsz=IMGSZ)
zip_path = shutil.make_archive("club_detector_coreml", "zip",
                               root_dir=os.path.dirname(pkg), base_dir=os.path.basename(pkg))
from google.colab import files; files.download(zip_path)
print("✅ downloaded club_detector_coreml.zip — model is now safe in two places")
''')

code('''
# 6) Evaluate — the verdict is the CLUB-HEAD mAP (higher = better; v1 was ~0.02)
from ultralytics import YOLO
metrics = YOLO(WEIGHTS).val()
print("box mAP50   :", round(float(metrics.box.map50), 3))
print("box mAP50-95:", round(float(metrics.box.map), 3))
for i, c in enumerate(metrics.box.ap_class_index):
    print(f"  class {c}  mAP50={metrics.box.ap50[i]:.3f}")
''')

md("""
### 7) Reality check (optional, last) — run on your own swing
Upload a **down-the-line** clip via the **Files panel** (folder icon → Upload), set `CLIP` to its
path, and run. It processes **every 3rd frame** (`vid_stride=3`) to stay light — this is the step
that was crashing the runtime, and your model is already saved, so it's safe now.
""")

code('''
# 7) Test on your own clip (upload via the Files panel first)
import os
from ultralytics import YOLO
CLIP = "/content/IMG_3927.MOV"   # <- set to your uploaded file's path
if os.path.exists(CLIP):
    YOLO(WEIGHTS).predict(CLIP, save=True, conf=0.25, vid_stride=3)
    print("done -> runs/detect/predict*/ (open in the Files panel). Watch the downswing.")
else:
    print("Set CLIP to your uploaded video path (folder icon on the left -> Upload).")
''')

md("""
## Read the result
- **Cell 6** is the accuracy verdict — the **club-head mAP50** (>0.6 solid, 0.3–0.6 usable with
  tracking, <0.2 retry). The classes may be unnamed numbers; **cell 7's annotated clip** tells you
  which number sits on the clubhead.
- Your model is saved in **Drive** (`MyDrive/golf/club_best.pt`) and downloaded as
  **`club_detector_coreml.zip`** — send me the zip + which class is the clubhead + how the downswing
  looked, and I'll build the shaft → **swing plane → on-plane / over-the-top** + a down-the-line mode.

**Credit:** dataset from Roboflow Universe (CC BY 4.0); base YOLO11n (Ultralytics, AGPL). Both credited in the repo.
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
