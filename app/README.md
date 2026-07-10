# Swing Check — phone web app (prototype)

A **client-side** swing analyzer: record/upload a swing → it finds the key positions →
it flags faults. Runs **entirely in the phone browser** (MediaPipe pose in WebAssembly +
the fault math) — **no server, no install, no App Store.**

```
video → MediaPipe pose (on-device) → Address/Top/Impact (heuristic, adjustable) → faults
```

## Open it on your phone
It needs to be served over HTTPS (browsers require a secure context for the camera,
ES-module imports, and the WASM pose model). Two easy ways:

**A) GitHub Pages (no server — recommended)**
1. Push this repo (`git push`).
2. GitHub → repo **Settings → Pages → Source: Deploy from a branch → `main` / `/ (root)`** → Save.
3. Wait ~1 min, then on your phone open:
   **`https://graceyan212.github.io/golf-swing/app/`**
4. Tap *Record or choose a swing video* → record face-on → wait for the analysis.

**B) Local (desktop test)**
```bash
cd app && python3 -m http.server 8000      # localhost is a secure context
# open http://localhost:8000  in a desktop browser (upload a swing clip)
```

## What's verified vs. what needs a real device
- ✅ **Fault math is verified** — `biomechanics.js` is a line-for-line port of
  `swing/biomechanics.py`, checked identical on 3 cases by `node test_biomechanics.mjs`.
- ✅ **`app.js` parses as valid ES module**; all UI element IDs are wired to `index.html`.
- ⚠️ **Not yet run on a physical phone by me** (no device in the build env). The pieces that
  need a real browser to confirm: the MediaPipe model download, frame sampling from the
  uploaded video (iOS seeking can be finicky), and on-device speed. If the first run misbehaves,
  open the browser console — errors show there — and it's usually a one-line tweak (e.g. sampling
  strategy or the wasm/model URL). Everything is deliberately dependency-light to make that easy.

## Honest limitations
- **Events use a pose heuristic, not the trained model.** Address = first frame you're in
  frame; Top = hands highest; Impact = hands back down near address height. It's rough — that's
  why the **sliders** let you drag each position to the right frame (and it doubles as a way to
  learn the 8 positions). The *accurate* event detector is the trained SLM in this repo — see below.
- **Fault thresholds are v1** and **2D / single-view** — same caveats as the Python layer
  (a tight sway cutoff, face-on only). Good enough to catch a real sway; not a coaching product.

## Plugging in the trained model (the accurate path)
The heuristic is a stand-in for our trained sequencer (42.9% PCE). To use the real model:

- **Backend (fastest):** wrap `swing/analyze.py` in a tiny FastAPI/Flask endpoint (or a Colab
  cell + ngrok) that takes a video and returns the 8 event frames. Then replace `pickEvents()`
  in `app.js` with a `fetch()` to that endpoint. The model + torch already run on Colab.
- **On-device (fully offline):** convert `models/swingnet_ours.pth.tar` → ONNX → run with
  `onnxruntime-web` (or TF.js) in the browser. More work, but then the whole app is client-side.

## Files
```
index.html            UI (mobile-first) + styles
app.js                pose sampling, event heuristic, rendering (ES module)
biomechanics.js       verified port of swing/biomechanics.py
test_biomechanics.mjs node parity test vs the Python (run: node test_biomechanics.mjs)
```
