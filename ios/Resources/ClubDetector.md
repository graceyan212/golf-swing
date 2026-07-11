# ClubDetector.mlpackage

YOLO11n object detector, fine-tuned **locally on an M4** on the Roboflow
**golf-club-tracking** dataset (9,456 train imgs). **mAP50 0.861** (val).

- Input: `image` 640x640 RGB.
- Output: `var_1223`, shape **(1, 7, 8400)** — raw head, no NMS wrapper
  (Ultralytics' nms=True CoreML export mislabels class count, so we decode raw).
  Channels per anchor: `[cx, cy, w, h, s0, s1, s2]` (box then 3 class scores).
- **Class mapping** (verified visually): index **0 = shaft**, **1 = clubhead**, **2 = grip**.
  (Ultralytics names are '0','1','3' respectively.)
- Swift decode: transpose to (8400,7), argmax over the 3 class scores, confidence
  threshold, NMS; shaft line = **grip(2) center -> clubhead(1) center**.

Dataset: Roboflow Universe golf-club-tracking (CC BY 4.0). Base: YOLO11n (Ultralytics, AGPL).
