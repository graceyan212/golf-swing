// app.js — client-side swing analyzer. Runs entirely in the phone browser:
// upload/record a swing -> MediaPipe pose on sampled frames -> heuristic
// Address/Top/Impact (adjustable) -> biomechanics faults (verified port).
// No backend. The accurate trained sequencer is a documented next step (see README).
import { PoseLandmarker, FilesetResolver } from
  "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@latest/vision_bundle.mjs";
import { analyze } from "./biomechanics.js";

const MODEL_URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/" +
  "pose_landmarker_lite/float16/latest/pose_landmarker_lite.task";
const WASM = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@latest/wasm";
const N_SAMPLES = 36;                     // evenly-spaced frames to analyze
const VIS = 0.3;                          // min landmark visibility to trust a frame
// MediaPipe pose landmark indices
const NOSE = 0, LSH = 11, RSH = 12, LEL = 13, REL = 14, LWR = 15, RWR = 16,
      LHIP = 23, RHIP = 24, LKN = 25, RKN = 26, LAN = 27, RAN = 28;
const DRAW_IDX = [NOSE, LSH, RSH, LEL, REL, LWR, RWR, LHIP, RHIP, LKN, RKN, LAN, RAN];
const BONES = [[LSH, RSH], [LSH, LHIP], [RSH, RHIP], [LHIP, RHIP], [LSH, LEL],
  [LEL, LWR], [RSH, REL], [REL, RWR], [LHIP, LKN], [LKN, LAN], [RHIP, RKN],
  [RKN, RAN], [NOSE, LSH], [NOSE, RSH]];

const $ = (id) => document.getElementById(id);
let landmarker = null;
let state = null;          // { video, W, H, dur, frames }
let events = null;         // { Address, Top, Impact } -> frame index
let active = "Address";

function status(msg, kind = "") {
  const el = $("status");
  el.textContent = msg;
  el.className = "status " + kind;
}

async function initLandmarker() {
  if (landmarker) return landmarker;
  status("loading pose model…");
  const vision = await FilesetResolver.forVisionTasks(WASM);
  landmarker = await PoseLandmarker.createFromOptions(vision, {
    baseOptions: { modelAssetPath: MODEL_URL, delegate: "GPU" },
    runningMode: "IMAGE", numPoses: 1,
    minPoseDetectionConfidence: 0.5, minPosePresenceConfidence: 0.5, minTrackingConfidence: 0.5,
  });
  return landmarker;
}

function loadVideo(file) {
  return new Promise((resolve, reject) => {
    const video = document.createElement("video");
    video.playsInline = true; video.muted = true; video.preload = "auto";
    video.src = URL.createObjectURL(file);
    video.onloadeddata = () => resolve(video);
    video.onerror = () => reject(new Error("couldn't load that video file"));
  });
}

function seekTo(video, t) {
  return new Promise((resolve) => {
    let done = false;
    const fin = () => { if (done) return; done = true; video.removeEventListener("seeked", fin); resolve(); };
    video.addEventListener("seeked", fin);
    video.currentTime = t;
    setTimeout(fin, 500);                 // fallback if 'seeked' never fires (some mobile browsers)
  });
}

function parseFrame(res, W, H, t) {
  const lm = res && res.landmarks && res.landmarks[0];
  if (!lm) return { t, ok: false };
  const need = [NOSE, LSH, RSH, LHIP, RHIP];
  if (!need.every((k) => (lm[k].visibility ?? 1) >= VIS)) return { t, ok: false };
  const px = (k) => ({ x: lm[k].x * W, y: lm[k].y * H });
  const draw = {};
  for (const k of DRAW_IDX) draw[k] = { x: lm[k].x, y: lm[k].y };
  return {
    t, ok: true,
    pose: { nose: px(NOSE), left_shoulder: px(LSH), right_shoulder: px(RSH), left_hip: px(LHIP), right_hip: px(RHIP) },
    wrists: { left: px(LWR), right: px(RWR) },
    draw,
  };
}

async function processVideo(file) {
  await initLandmarker();
  const video = await loadVideo(file);
  try { await video.play(); video.pause(); } catch (e) { /* prime decoder for iOS */ }
  const W = video.videoWidth || 640, H = video.videoHeight || 480, dur = video.duration;
  if (!dur || !isFinite(dur)) throw new Error("couldn't read the video length — try a different clip");
  const cvs = document.createElement("canvas"); cvs.width = W; cvs.height = H;
  const ctx = cvs.getContext("2d");
  const frames = [];
  for (let i = 0; i < N_SAMPLES; i++) {
    const t = Math.min((dur * (i + 0.5)) / N_SAMPLES, Math.max(0, dur - 0.01));
    await seekTo(video, t);
    ctx.drawImage(video, 0, 0, W, H);
    let res = null;
    try { res = landmarker.detect(cvs); } catch (e) { /* skip bad frame */ }
    frames.push(parseFrame(res, W, H, t));
    status(`analyzing swing… ${Math.round(((i + 1) / N_SAMPLES) * 100)}%`, "busy");
  }
  return { video, W, H, dur, frames };
}

// Transparent heuristic for the 3 events we need. Users adjust with the sliders.
function pickEvents(frames) {
  const ok = frames.filter((f) => f.ok);
  if (ok.length < 3) return null;
  const n = frames.length;
  const handY = (f) => Math.min(f.wrists.left.y, f.wrists.right.y);   // higher hand (y grows downward)
  const idxOf = (f) => frames.indexOf(f);
  const address = ok.find((f) => idxOf(f) <= n * 0.2) || ok[0];
  const ai = idxOf(address);
  let top = null;                                   // hands highest in the first ~70%
  for (const f of ok) { const i = idxOf(f); if (i > ai && i <= n * 0.7 && (!top || handY(f) < handY(top))) top = f; }
  top = top || ok[Math.floor(ok.length / 2)];
  const ti = idxOf(top);
  const addrHandY = handY(address);
  let impact = null, best = Infinity;               // after Top, hands back down near address height
  for (const f of ok) { const i = idxOf(f); if (i > ti) { const d = Math.abs(handY(f) - addrHandY); if (d < best) { best = d; impact = f; } } }
  impact = impact || ok[ok.length - 1];
  return { Address: ai, Top: ti, Impact: idxOf(impact) };
}

function drawSkeleton(ctx, draw, W, H) {
  ctx.lineWidth = Math.max(2, W / 160);
  ctx.strokeStyle = "#39d98a"; ctx.fillStyle = "#39d98a";
  for (const [a, b] of BONES) {
    if (!draw[a] || !draw[b]) continue;
    ctx.beginPath(); ctx.moveTo(draw[a].x * W, draw[a].y * H); ctx.lineTo(draw[b].x * W, draw[b].y * H); ctx.stroke();
  }
  for (const k of DRAW_IDX) {
    if (!draw[k]) continue;
    ctx.beginPath(); ctx.arc(draw[k].x * W, draw[k].y * H, Math.max(3, W / 110), 0, 7); ctx.fill();
  }
}

async function showEvent(name) {
  active = name;
  for (const n of ["Address", "Top", "Impact"]) $("tab" + n).classList.toggle("on", n === name);
  const f = state.frames[events[name]];
  const c = $("view"); c.width = state.W; c.height = state.H;
  const ctx = c.getContext("2d");
  await seekTo(state.video, f.t);
  ctx.drawImage(state.video, 0, 0, state.W, state.H);
  if (f.ok) drawSkeleton(ctx, f.draw, state.W, state.H);
  else { ctx.fillStyle = "rgba(0,0,0,.5)"; ctx.fillRect(0, 0, state.W, state.H); ctx.fillStyle = "#fff"; ctx.font = `${state.W / 22}px sans-serif`; ctx.fillText("no body detected in this frame", state.W * 0.08, state.H / 2); }
  $("caption").textContent = `${name} — frame ${events[name] + 1}/${state.frames.length}` + (f.ok ? "" : " (drag the slider to a frame where you're in view)");
}

function renderFaults() {
  const poses = {};
  for (const n of ["Address", "Top", "Impact"]) { const f = state.frames[events[n]]; if (f.ok) poses[n] = f.pose; }
  const faults = analyze(poses);
  const box = $("faults");
  if (Object.keys(poses).length < 3) {
    box.innerHTML = `<div class="clean">Pose missing at one or more positions — drag the sliders so your full body is visible at Address, Top, and Impact.</div>`;
    return;
  }
  if (!faults.length) { box.innerHTML = `<div class="clean">✓ No major faults flagged — sway, hip slide, and early extension are all within range.</div>`; return; }
  box.innerHTML = faults.map((f) => `<div class="fault"><b>${f.fault.replace(/_/g, " ")}</b><br>${f.note}</div>`).join("");
}

function buildControls() {
  $("app").hidden = false;
  const n = state.frames.length - 1;
  for (const name of ["Address", "Top", "Impact"]) {
    const s = $("sl" + name); s.max = n; s.value = events[name];
    s.oninput = () => { events[name] = +s.value; renderFaults(); $("caption").textContent = `${name} — frame ${+s.value + 1}/${state.frames.length}`; active = name; markTab(name); };
    s.onchange = () => showEvent(name);
    $("tab" + name).onclick = () => showEvent(name);
  }
}
function markTab(name) { for (const n of ["Address", "Top", "Impact"]) $("tab" + n).classList.toggle("on", n === name); }

async function onFile(file) {
  try {
    $("app").hidden = true;
    state = await processVideo(file);
    const okCount = state.frames.filter((f) => f.ok).length;
    if (okCount < 3) { status("couldn't track your body — film face-on, full body in frame, good light, and trim to just the swing.", "err"); return; }
    events = pickEvents(state.frames);
    buildControls();
    renderFaults();
    await showEvent("Address");
    status(`done — ${okCount}/${state.frames.length} frames tracked. Auto-detected positions are approximate; drag a slider to fix any that are off.`, "ok");
  } catch (e) {
    status("error: " + e.message, "err");
  }
}

$("file").addEventListener("change", (e) => { if (e.target.files[0]) onFile(e.target.files[0]); });
status("ready — pick or record a face-on swing video to analyze.");
