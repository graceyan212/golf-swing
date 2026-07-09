"""Per-frame 2D pose extraction via MediaPipe Tasks (PoseLandmarker) — off-the-shelf
model, auto-downloaded. Maps the 33 landmarks to the 5 joints the biomechanics layer
needs. Coordinates in pixels (x right, y down), matching swing/biomechanics.py.
"""
from __future__ import annotations
import os, ssl, urllib.request
import cv2

# MediaPipe Pose landmark indices -> our COCO-ish joint names
_MP_IDX = {"nose": 0, "left_shoulder": 11, "right_shoulder": 12,
           "left_hip": 23, "right_hip": 24}
_MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
              "pose_landmarker_lite/float16/latest/pose_landmarker_lite.task")
_MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                           "data", "pose_landmarker_lite.task")


def _ensure_model() -> str:
    p = os.path.abspath(_MODEL_PATH)
    if not os.path.exists(p):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        try:
            import certifi
            ctx = ssl.create_default_context(cafile=certifi.where())
        except Exception:
            ctx = ssl._create_unverified_context()
        with urllib.request.urlopen(_MODEL_URL, context=ctx) as r, open(p, "wb") as f:
            f.write(r.read())
    return p


def _make_detector():
    from mediapipe.tasks import python
    from mediapipe.tasks.python import vision
    opts = vision.PoseLandmarkerOptions(
        base_options=python.BaseOptions(model_asset_path=_ensure_model()),
        running_mode=vision.RunningMode.IMAGE)
    return vision.PoseLandmarker.create_from_options(opts)


def _upscale(frame, min_side=384):
    h, w = frame.shape[:2]
    s = max(1.0, min_side / max(h, w))
    return cv2.resize(frame, (int(w * s), int(h * s))) if s > 1.0 else frame


def _joints(result, w, h):
    if not result.pose_landmarks:
        return None
    lm = result.pose_landmarks[0]                      # first detected person
    if any(lm[i].visibility < 0.3 for i in _MP_IDX.values()):
        return None
    return {name: (lm[i].x * w, lm[i].y * h) for name, i in _MP_IDX.items()}


def pose_at_frames(video_path: str, frame_indices) -> dict:
    """Return {frame_idx: pose_dict or None} for the requested frames.
    pose_dict = {joint: (x_px, y_px)} for nose + L/R shoulders + L/R hips."""
    import mediapipe as mp
    det = _make_detector()
    cap = cv2.VideoCapture(video_path)
    out = {}
    for idx in sorted({int(i) for i in frame_indices}):
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ok, frame = cap.read()
        if not ok:
            out[idx] = None
            continue
        frame = _upscale(frame)
        h, w = frame.shape[:2]
        mp_img = mp.Image(image_format=mp.ImageFormat.SRGB,
                          data=cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
        out[idx] = _joints(det.detect(mp_img), w, h)
    cap.release()
    return out
