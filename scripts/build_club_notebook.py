"""Builds train/colab_club_detector.ipynb (valid JSON). Run: python3 scripts/build_club_notebook.py

Fine-tunes a small COCO-pretrained YOLO11n (detection) on a *large* golf-club dataset so it
locates the club head with a bounding box. Clubhead box + hands (from Vision) -> shaft line ->
swing plane. Same transfer-learning recipe as the swing model; detection needs far less data
per class than keypoints, and we point it at a 6,750-image set (the last one had ~13 images)."""
import json
from pathlib import Path

C = []
def md(s): C.append(("markdown", s.strip("\n")))
def code(s): C.append(("code", s.strip("\n")))

md("""
# Golf Club Detector v2 — fine-tune YOLO11n (detection) on a big dataset

Trains a **clubhead detector** for the swing-plane feature. Lessons from v1 baked in:
- **Way more data.** v1 used a ~13-image set and scored ~0 — useless. This points at a
  **6,750-image** golf-club dataset.
- **Detection, not keypoints.** A bounding box is much easier to learn with this much data;
  clubhead-box center + your **hands** (from Vision) gives the **shaft line** for plane.
- **Reliable download.** The export **zips** the Core ML model so it actually lands on your
  computer (a raw `.mlpackage` is a folder and Colab's downloader drops it).

Same transfer-learning recipe as your swing model: small COCO-pretrained base → fine-tune on
task data. We **check accuracy before** building anything on top.
""")

code("""
# 1) Install
%%capture
!pip install -q ultralytics roboflow coremltools
""")

md("""
### One-time setup
1. Free account at **roboflow.com** → **Settings → API Key** → paste into `ROBOFLOW_API_KEY`.
2. Defaults below point at the **6,750-image** `golf-club-tracking` dataset. If the download
   errors on the slugs, open its Roboflow page → **Download Dataset → YOLOv8** and copy the exact
   `workspace / project / version` from the snippet it shows.
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
print("---- data.yaml (classes this model will learn) ----")
print(open(DATA_YAML).read())
# sanity check the size — this should be THOUSANDS, not a handful
import glob, os
for split in ["train", "valid", "test"]:
    p = os.path.join(dataset.location, split, "images")
    if os.path.isdir(p): print(f"{split}: {len(glob.glob(p + '/*'))} images")
''')

code('''
# 4) Fine-tune (COCO-pretrained base -> specialize on golf clubs)
from ultralytics import YOLO
model = YOLO(BASE)
model.train(data=DATA_YAML, epochs=EPOCHS, imgsz=IMGSZ, batch=BATCH, patience=PATIENCE,
            device=0, plots=True)
print("best weights:", model.trainer.best)
''')

code('''
# 5) Evaluate — what matters is the CLUB-HEAD mAP (higher = better)
metrics = model.val()
print("box mAP50   :", round(float(metrics.box.map50), 3))
print("box mAP50-95:", round(float(metrics.box.map), 3))
# per-class, so we can read the club-head number specifically:
for i, c in enumerate(metrics.box.ap_class_index):
    print(f"  class {model.names[int(c)]:20s} mAP50={metrics.box.ap50[i]:.3f}")
''')

md("""
### 6) Reality check — run it on a real swing
Upload a **down-the-line** swing (camera behind you). Watch the **downswing** frames — that's
where the club blurs and detection is hardest. This is the honest test before we build anything.
""")

code('''
# 6) Test on your own clip
import os
from google.colab import files
print("Upload a down-the-line swing video (.mp4/.mov):")
up = files.upload()
test_video = list(up.keys())[0] if up else ""
if test_video and os.path.exists(test_video):
    model.predict(source=test_video, save=True, conf=0.25)   # annotated clip -> runs/detect/predict*
    print("Annotated result saved under runs/detect/ — scrub the DOWNSWING frames.")
else:
    print("No clip uploaded — skip to export, or set test_video to a file path.")
''')

code('''
# 7) Export to Core ML, ZIP it, and download (zip so it actually lands on your Mac)
import shutil, os
pkg = model.export(format="coreml", nms=True, imgsz=IMGSZ)   # produces a .mlpackage FOLDER
zip_path = shutil.make_archive("club_detector_coreml", "zip",
                               root_dir=os.path.dirname(pkg), base_dir=os.path.basename(pkg))
print("zipped Core ML model:", zip_path)
from google.colab import files
files.download(zip_path)   # unzip on your Mac to get the .mlpackage; send it to me
''')

md("""
## Read the result
- **Cell 5** is the verdict: the **club-head mAP50**. Roughly — >0.6 is solid, 0.3–0.6 is usable
  with tracking, <0.2 means try more epochs / a different dataset. (v1 was ~0.02.)
- **Cell 6** is the real-world tell: does it track the club through the **downswing**? If it drops
  out mid-swing (the blur problem), we bridge gaps with tracking (Kalman) at integration time.
- Send me the **`club_detector_coreml.zip`** + the mAP + what the test clip looked like. Then I wire
  it in: clubhead box + your hands (Vision) → shaft → **swing plane → on-plane / over-the-top**, in
  a down-the-line mode. We measure before trusting it — every time.

**Credit:** dataset from Roboflow Universe (CC BY 4.0 — check the page); base YOLO11n (Ultralytics,
AGPL). Both credited in the repo.
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
