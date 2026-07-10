"""Builds train/colab_club_detector.ipynb (valid JSON). Run: python3 scripts/build_club_notebook.py

Fine-tunes a small COCO-pretrained YOLO11n-pose base on a golf-club keypoint dataset so it
locates the club (grip + head) -> shaft line for swing-plane analysis. Same transfer-learning
recipe as the swing sequencer (start from a pretrained base, train on task data)."""
import json
from pathlib import Path

C = []
def md(s): C.append(("markdown", s.strip("\n")))
def code(s): C.append(("code", s.strip("\n")))

md("""
# Golf Club Detector — fine-tune YOLO11n-pose (Colab)

Trains a **club detector** for the down-the-line swing-plane feature. Same recipe as your swing
model: take a **small, COCO-pretrained base** (`yolo11n-pose`, nano = phone-friendly) and
**fine-tune it on a golf-club dataset** so it outputs the club as keypoints (grip + head). The
line grip→head is the **shaft**; tracked through the swing it gives the **swing plane**.

**Honest heads-up (measure, don't assume):**
- The **downswing motion-blur** is the known hard part — the club smears when it's moving fast,
  exactly where "over the top" happens. The **test cell** below runs the model on a real swing so
  you *see* the detection quality (especially the downswing) before we trust it.
- This produces a **Core ML** model you download; wiring it into the app (shaft → plane →
  on-plane / over-the-top, down-the-line mode) is the next step.
- First-run version nits are normal (like the swing notebook) — send me any error and we iterate.
""")

code("""
# 1) Install
%%capture
!pip install -q ultralytics roboflow coremltools
""")

md("""
### Get your dataset + key (one-time)
1. Make a free account at **roboflow.com** → **Settings → API Key** → copy it into `ROBOFLOW_API_KEY` below.
2. On the dataset's Roboflow Universe page, click **Download Dataset → YOLOv8** and it shows a code
   snippet with the exact `workspace / project / version`. The defaults below target the
   *photoFunction "golf swing"* keypoint dataset — **verify them against that snippet** (versions change).
""")

code('''
# 2) Config
ROBOFLOW_API_KEY = ""              # <- paste your free Roboflow API key
WORKSPACE = "photofunction"        # verify on the dataset's "Download Dataset" snippet
PROJECT   = "golf-swing-b21yo"
VERSION   = 1                      # <- set to the dataset's current version number
FORMAT    = "yolov8"               # Roboflow export format (yolov8 covers pose/keypoint)

BASE   = "yolo11n-pose.pt"         # small COCO-pretrained pose base (transfer learning)
EPOCHS = 80
IMGSZ  = 640
BATCH  = 16
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
print("---- data.yaml ----")
print(open(DATA_YAML).read())   # shows classes + keypoint shape the model will learn
''')

code('''
# 4) Fine-tune (starts from the pretrained base; trains the head on golf clubs)
from ultralytics import YOLO
model = YOLO(BASE)
model.train(data=DATA_YAML, epochs=EPOCHS, imgsz=IMGSZ, batch=BATCH, device=0, plots=True)
print("best weights:", model.trainer.best)
''')

code('''
# 5) Evaluate on the dataset's val split (mAP + pose metrics)
metrics = model.val()
print(metrics)
''')

md("""
### 6) Reality check — run it on a real swing
Upload a **down-the-line** swing clip (camera behind you, along the target line). Watch the
**downswing** frames: that's where blur hits hardest. This tells us honestly whether the detector
is good enough for plane before we build the app integration.
""")

code('''
# 6) Test on your own clip
import os
from google.colab import files
print("Upload a down-the-line swing video (.mp4/.mov):")
up = files.upload()
test_video = list(up.keys())[0] if up else ""
if test_video and os.path.exists(test_video):
    model.predict(source=test_video, save=True, conf=0.25)   # annotated clip -> runs/pose/predict*
    print("Annotated result saved under runs/pose/ — open it and scrub the DOWNSWING frames.")
else:
    print("No clip uploaded — skip, or set test_video to a file path.")
''')

code('''
# 7) Export to Core ML for the iPhone app, then download it
path = model.export(format="coreml", nms=True, imgsz=IMGSZ)
print("Core ML model at:", path)
from google.colab import files
files.download(path)   # send me this .mlpackage (or its .zip) to wire into the app
''')

md("""
## Read the result
- **mAP / pose metrics** (cell 5) = how well it finds the club on held-out images.
- **The uploaded-clip test** (cell 6) is the real tell — if the club is tracked cleanly through the
  **downswing**, the plane feature is viable; if it drops out mid-downswing, we add tracking
  (Kalman) to bridge the blurred frames, or reconsider.
- Send me the **Core ML model** + what the test clip looked like. Next: I wire it in — club keypoints
  + your hands (from Vision) → shaft → **swing plane** → *on-plane / over-the-top*, in a new
  down-the-line mode. We'll measure it before trusting it, same as everything else.

**Credit:** dataset from Roboflow Universe (check its license — CC BY etc.); base model YOLO11n-pose
(Ultralytics, AGPL). We'll note both in the repo.
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
