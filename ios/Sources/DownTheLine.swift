import SwiftUI
import AVFoundation
import PhotosUI
import UIKit

// Runs the club detector across a down-the-line swing, tracks the shaft (grip->clubhead),
// establishes the address plane, and gives a first-pass on-plane / over-the-top read.
@MainActor
final class PlaneAnalyzer: ObservableObject {
    @Published var status = "Record or choose a down-the-line swing (camera behind you)."
    @Published var busy = false
    @Published var progress: Double = 0
    @Published var dets: [ClubDetection] = []
    @Published var thumbs: [UIImage?] = []
    @Published var playhead = 0
    @Published var planeLine: (CGPoint, CGPoint)? = nil
    @Published var verdict: String? = nil        // "On plane" / "Over the top" / message
    @Published var overTop = false

    private let tracker = ClubTracker()
    private let n = 36

    func reset() {
        dets = []; thumbs = []; playhead = 0; planeLine = nil; verdict = nil; overTop = false
        busy = false; progress = 0
        status = "Record or choose a down-the-line swing (camera behind you)."
    }

    func analyze(url: URL) {
        busy = true; progress = 0; dets = []; thumbs = []; planeLine = nil; verdict = nil
        status = "Analyzing swing…"
        guard let tr = tracker else { busy = false; status = "Club model failed to load."; return }
        Task {
            let (ds, ts) = await Self.run(url: url, tracker: tr, n: n) { p in Task { @MainActor in self.progress = p } }
            self.dets = ds; self.thumbs = ts; self.playhead = 0
            self.computePlane()
            let tracked = ds.filter { $0.hasClub }.count
            self.busy = false
            self.status = "Done — club tracked in \(tracked)/\(ds.count) frames. Scrub to inspect. Plane read is a first pass — tune on device."
        }
    }

    nonisolated static func run(url: URL, tracker: ClubTracker, n: Int,
                                progress: @escaping (Double) -> Void) async -> ([ClubDetection], [UIImage?]) {
        let asset = AVURLAsset(url: url)
        let dur = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        guard dur > 0 else { return ([], []) }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        var ds: [ClubDetection] = []; var ts: [UIImage?] = []
        for i in 0..<n {
            let t = min(dur * (Double(i) + 0.5) / Double(n), max(0, dur - 0.01))
            if let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) {
                ds.append(tracker.detect(cg)); ts.append(UIImage(cgImage: cg))
            } else { ds.append(ClubDetection()); ts.append(nil) }
            progress(Double(i + 1) / Double(n))
        }
        return (ds, ts)
    }

    private func computePlane() {
        let clubIdx = dets.indices.filter { dets[$0].hasClub }
        guard clubIdx.count >= 4 else {
            verdict = "Couldn't track the club — film down-the-line, full club in frame, good light."
            return
        }
        let addr = clubIdx.first(where: { $0 <= dets.count * 3 / 10 }) ?? clubIdx.first!
        guard let ap = dets[addr].shaftLine else { return }
        planeLine = ap
        // top of backswing = clubhead highest (smallest y)
        let top = clubIdx.min(by: { dets[$0].clubhead!.y < dets[$1].clubhead!.y }) ?? addr
        // signed perpendicular distance of a point from the address plane line
        func signedDist(_ p: CGPoint) -> CGFloat {
            let (a, b) = ap; let dx = b.x - a.x, dy = b.y - a.y
            let len = max(sqrt(dx * dx + dy * dy), 1e-6)
            return ((p.x - a.x) * dy - (p.y - a.y) * dx) / len
        }
        let downswing = clubIdx.filter { $0 > top }
        let maxOutside = downswing.compactMap { dets[$0].clubhead.map { abs(signedDist($0)) } }.max() ?? 0
        overTop = maxOutside > 0.06          // normalized threshold — v1, tune on device
        verdict = overTop ? "Over the top" : "On plane"
    }
}

// Frame + reference plane line + current shaft line + clubhead/grip dots.
struct PlaneCanvas: View {
    let image: UIImage?
    let det: ClubDetection?
    let planeLine: (CGPoint, CGPoint)?
    var body: some View {
        let aspect = image?.size ?? CGSize(width: 9, height: 16)
        return Canvas { ctx, size in
            if let image { ctx.draw(ctx.resolve(Image(uiImage: image)), in: CGRect(origin: .zero, size: size)) }
            else { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.surface2)) }
            func P(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
            if let (a, b) = planeLine {           // reference plane, extended + dashed
                let A = P(a), B = P(b); let dx = B.x - A.x, dy = B.y - A.y
                var path = Path()
                path.move(to: CGPoint(x: A.x - dx * 2, y: A.y - dy * 2))
                path.addLine(to: CGPoint(x: B.x + dx * 2, y: B.y + dy * 2))
                ctx.stroke(path, with: .color(Palette.mist.opacity(0.6)), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            }
            if let sl = det?.shaftLine {          // current shaft
                var p = Path(); p.move(to: P(sl.0)); p.addLine(to: P(sl.1))
                ctx.stroke(p, with: .color(Palette.fairway), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if let h = det?.clubhead { ctx.fill(Path(ellipseIn: CGRect(x: P(h).x - 5, y: P(h).y - 5, width: 10, height: 10)), with: .color(Palette.amber)) }
            if let g = det?.grip { ctx.fill(Path(ellipseIn: CGRect(x: P(g).x - 4, y: P(g).y - 4, width: 8, height: 8)), with: .color(Palette.chalk)) }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .background(Color.black)
    }
}

struct DownTheLineSection: View {
    @StateObject private var an = PlaneAnalyzer()
    @State private var pick: PhotosPickerItem?
    @State private var showCam = false
    private var hasResult: Bool { !an.dets.isEmpty && an.playhead < an.dets.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if an.busy {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow("Analyzing", color: Palette.fairway)
                    ProgressView(value: an.progress).tint(Palette.fairway)
                }.card()
            }
            if hasResult { results } else if !an.busy { intro }
        }
        .onChange(of: pick) { _, it in load(it) }
        .fullScreenCover(isPresented: $showCam) { CameraRecorder { url in an.analyze(url: url) }.ignoresSafeArea() }
        .onAppear { if CommandLine.arguments.contains("-dtldemo") && an.dets.isEmpty && !an.busy { runDemo() } }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Swing plane").font(.display(30)).foregroundStyle(Palette.chalk)
            Text("Film from **down-the-line** — camera behind you, looking down the target line. Tracks your club and checks if you're on plane or over the top.")
                .font(.system(size: 15)).foregroundStyle(Palette.mist)
            VStack(spacing: 10) {
                Button { if cameraAvailable { showCam = true } } label: { Label("Record a swing", systemImage: "video.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(FairwayButton()).disabled(!cameraAvailable)
                if !cameraAvailable {
                    Text("Recording needs a real device — use Choose or the demo in the Simulator.")
                        .font(.system(size: 12)).foregroundStyle(Palette.mist).frame(maxWidth: .infinity)
                }
                PhotosPicker(selection: $pick, matching: .videos) { Label("Choose from library", systemImage: "photo.on.rectangle.angled").frame(maxWidth: .infinity) }
                    .buttonStyle(GhostButton())
                if Bundle.main.url(forResource: "demo_swing", withExtension: "mp4") != nil {
                    Button { runDemo() } label: { Label("Try the demo clip", systemImage: "play.circle").frame(maxWidth: .infinity) }.buttonStyle(GhostButton())
                }
            }
            Text(an.status).font(.footnote).foregroundStyle(Palette.mist)
        }
    }

    private var results: some View {
        let color = an.overTop ? Palette.flag : Palette.fairway
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: an.overTop ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 30)).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow("Swing plane")
                    Text(an.verdict ?? "—").font(.display(24)).foregroundStyle(Palette.chalk)
                    Text("first-pass read — dashed line is your address plane").font(.system(size: 12)).foregroundStyle(Palette.mist)
                }
            }.card()

            VStack(alignment: .leading, spacing: 10) {
                PlaneCanvas(image: an.playhead < an.thumbs.count ? an.thumbs[an.playhead] : nil,
                            det: an.playhead < an.dets.count ? an.dets[an.playhead] : nil,
                            planeLine: an.planeLine)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Eyebrow("Frame \(an.playhead + 1) / \(an.dets.count)")
                Filmstrip(thumbs: an.thumbs, total: an.dets.count, playhead: $an.playhead, events: [:])
            }.card(10)

            Text(an.status).font(.footnote).foregroundStyle(Palette.mist)
            Button { an.reset() } label: { Label("Analyze another", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
                .buttonStyle(GhostButton())
        }
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let movie = try? await item.loadTransferable(type: Movie.self) { an.analyze(url: movie.url) }
            else { an.status = "Couldn't load that video." }
        }
    }
    private func runDemo() {
        if let u = Bundle.main.url(forResource: "demo_swing", withExtension: "mp4") { an.analyze(url: u) }
    }
}
