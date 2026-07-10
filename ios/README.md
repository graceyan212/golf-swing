# Swing Check — native iOS app (SwiftUI)

A native iPhone app: record/pick a swing → **Apple Vision** finds your body on-device →
the **verified biomechanics logic** (ported from `swing/biomechanics.py`) flags faults.
No third-party dependencies, no server.

```
video → Vision body pose (on-device) → Address/Top/Impact (heuristic, adjustable) → faults
```

## Status — what's verified (and the one thing that isn't)
- ✅ **Builds cleanly** — Xcode 26.6 / iOS 26 SDK, `xcodebuild … BUILD SUCCEEDED`.
- ✅ **Runs in the Simulator** — installs, launches, full UI renders (buttons, sliders, report).
- ✅ **Whole analysis pipeline verified on real clips** — the app's *actual* `Models.swift` +
  `Biomechanics.swift` were compiled with a macOS driver and run through Vision on real
  GolfDB clips, producing correct events + faults, e.g.:
  ```
  clip 10:  tracked 35/36  A=0 T=25 I=35  → sway off ball (0.61) + early extension (9.6°)
  clip 20:  tracked 36/36  A=0 T=2  I=15  → no faults (clean)
  ```
- ✅ **Fault math == Python** (same constants/geometry; the JS port of the same logic is
  unit-checked identical in `../app/`).
- ⚠️ **The analysis does not run in the iOS Simulator.** `VNDetectHumanBodyPoseRequest`
  returns **0** poses in the Simulator (measured: `tracked=0/36`) — a known Apple Simulator
  limitation; body pose needs real-device hardware. macOS Vision tracked the *same* clip
  30/36, so the clip and code are sound. **It must be run on a physical iPhone** to analyze.
  This is the only piece I could not verify here (no device / code-signing in the build env).

## Build & run
```bash
cd ios
xcodegen generate            # regenerate the project from project.yml (or just open the .xcodeproj)
open SwingCheck.xcodeproj
```
- **On your iPhone (required for analysis):** in Xcode select the *SwingCheck* target →
  *Signing & Capabilities* → pick your Team (a free Apple ID works) → plug in your iPhone,
  select it, press ▶. Approve the app on the phone (Settings → General → VPN & Device
  Management) the first time. Grant camera/photos, then *Record a swing* face-on.
- **In the Simulator:** the UI runs and you can drive it, but pose analysis returns nothing
  (see above). Use a device.

## How it works
- `PoseExtractor.swift` — samples 36 frames with `AVAssetImageGenerator`, upscales, runs
  `VNDetectHumanBodyPoseRequest`, maps Vision joints → pixel-space `Pose` (y-flipped), and a
  transparent heuristic picks Address/Top/Impact.
- `Biomechanics.swift` — sway / hip-slide / early-extension from geometry (port of the Python).
- `ContentView.swift` — pick/record/demo, a pose-overlay canvas, a segmented control + three
  sliders to correct the positions, and the fault report.
- `Analyzer.swift` — orchestrates off the main actor; publishes results to the UI.

## Honest limitations
- **Events use a heuristic, not the trained model** — same as the web app. The sliders let you
  fix any mis-picked position (some are rough, e.g. a noisy "Top").
- **Fault thresholds are v1**, **2D / single-view** — same caveats as the Python layer.
- **Recording needs a device**; the Simulator has no camera (use the photo picker / demo there,
  but analysis still needs a device per above).

## Plug in the trained model (accurate events)
Convert `models/swingnet_ours.pth.tar` → **Core ML** (`coremltools`, via ONNX) and run it with
the Vision/Core ML stack in `PoseExtractor`, replacing `pickEvents`. Then event detection matches
the trained SLM (42.9% PCE) instead of the heuristic. Alternatively call a backend that runs
`swing/analyze.py`.

## Credit
`Resources/demo_swing.mp4` is a single sample clip from **GolfDB** (McNally et al.), included only
as a built-in demo. Pose by Apple Vision.
