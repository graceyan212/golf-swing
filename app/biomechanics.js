// biomechanics.js — exact JS port of swing/biomechanics.py (the fault layer).
// Runs in the browser so the whole fault analysis happens on-device.
// Pose = { joint: {x, y} } in image PIXELS (x right, y down), joints:
// nose, left_shoulder, right_shoulder, left_hip, right_hip.
// Keep this in lockstep with swing/biomechanics.py — tests/ verifies parity.

export const REQUIRED_JOINTS = ["nose", "left_shoulder", "right_shoulder", "left_hip", "right_hip"];
export const DEFAULT_THRESH = { sway: 0.40, slide: 0.70, early_ext: 8.0 };

const mid = (a, b) => ({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 });
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const midShoulder = (p) => mid(p.left_shoulder, p.right_shoulder);
const midHip = (p) => mid(p.left_hip, p.right_hip);
const shoulderWidth = (p) => Math.max(dist(p.left_shoulder, p.right_shoulder), 1e-6);

// Lateral spine tilt (deg from vertical): angle of the hip->shoulder line.
export function spineTilt(p) {
  const ms = midShoulder(p), mh = midHip(p);
  const dx = ms.x - mh.x, dy = ms.y - mh.y;
  return (Math.atan2(Math.abs(dx), Math.abs(dy)) * 180) / Math.PI;
}

// Signed horizontal shift in shoulder-widths (+ = toward image-right).
const lat = (ref, now, sw) => (now.x - ref.x) / sw;

const r2 = (x) => Math.round(x * 100) / 100;
const r1 = (x) => Math.round(x * 10) / 10;
const sgn2 = (x) => (x >= 0 ? "+" : "") + x.toFixed(2);

// poses: { Address, Top, Impact } -> array of fault objects (value/threshold/note).
export function analyze(poses, thresh) {
  const t = { ...DEFAULT_THRESH, ...(thresh || {}) };
  const faults = [];
  const A = poses.Address, T = poses.Top, I = poses.Impact;

  if (A && T) {
    const sway = lat(A.nose, T.nose, shoulderWidth(A));
    if (Math.abs(sway) > t.sway) {
      faults.push({
        fault: "sway_off_ball", events: ["Address", "Top"],
        value: r2(sway), threshold: t.sway,
        note: `head slides ${sgn2(sway)} shoulder-widths on the backswing ` +
              `(steady is within ±${t.sway}) — you're swaying off the ball instead of turning`,
      });
    }
  }
  if (A && I) {
    const slide = lat(midHip(A), midHip(I), shoulderWidth(A));
    if (Math.abs(slide) > t.slide) {
      faults.push({
        fault: "hip_slide", events: ["Address", "Impact"],
        value: r2(slide), threshold: t.slide,
        note: `hips slide ${sgn2(slide)} shoulder-widths laterally by impact ` +
              `(>${t.slide}) — driving past the ball instead of rotating`,
      });
    }
    const drop = spineTilt(A) - spineTilt(I); // + = spine straightened toward vertical
    if (drop > t.early_ext) {
      faults.push({
        fault: "early_extension", events: ["Address", "Impact"],
        value: r1(drop), threshold: t.early_ext,
        note: `spine straightens ${Math.round(drop)}deg from address to impact ` +
              `(>${t.early_ext}) — early extension / standing up through the shot`,
      });
    }
  }
  return faults;
}

export function report(poses, thresh) {
  const faults = analyze(poses, thresh);
  if (!faults.length) return "No major faults flagged (sway / hip slide / early extension within range).";
  return "Faults:\n" + faults.map((f) => `  - ${f.fault}: ${f.note}`).join("\n");
}
