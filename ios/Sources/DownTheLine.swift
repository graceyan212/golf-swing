import SwiftUI
import AVFoundation
import PhotosUI
import UIKit

// Runs the club detector across a down-the-line swing, tracks the shaft (grip->clubhead),
// establishes the address plane, and gives a first-pass on-plane / over-the-top read.
@MainActor
final class PlaneAnalyzer: ObservableObject {
    @Published var status = "Record or pick a swing filmed from behind you."
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
        status = "Looking at your swing…"
        guard let tr = tracker else { busy = false; status = "Couldn't start. Please try again."; return }
        Task {
            let (ds, ts) = await Self.run(url: url, tracker: tr, n: n) { p in Task { @MainActor in self.progress = p } }
            self.dets = ds; self.thumbs = ts; self.playhead = 0
            self.computePlane()
            self.busy = false
            self.status = "All done. Slide to watch your swing."
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
            verdict = "We couldn't follow your club. Film from behind you with the whole club in view, in good light."
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
        verdict = overTop ? "Coming over the top" : "Good swing path"
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

/// Side (down-the-line) results, driven by a PlaneAnalyzer the parent owns.
struct PlaneResultsView: View {
    @ObservedObject var an: PlaneAnalyzer
    private var tracked: Bool { an.planeLine != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: !tracked ? "questionmark.circle.fill"
                                  : (an.overTop ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                    .font(.system(size: 30))
                    .foregroundStyle(!tracked ? Palette.amber : (an.overTop ? Palette.flag : Palette.fairway))
                VStack(alignment: .leading, spacing: 4) {
                    Text(an.verdict ?? "—").font(.display(tracked ? 26 : 20)).foregroundStyle(Palette.chalk)
                        .fixedSize(horizontal: false, vertical: true)
                    if tracked {
                        Text(an.overTop ? "Your club swings out and over on the way down."
                                        : "Your club stays on a nice path down to the ball.")
                            .font(.system(size: 16)).foregroundStyle(Palette.mist).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.card()

            VStack(alignment: .leading, spacing: 10) {
                PlaneCanvas(image: an.playhead < an.thumbs.count ? an.thumbs[an.playhead] : nil,
                            det: an.playhead < an.dets.count ? an.dets[an.playhead] : nil,
                            planeLine: an.planeLine)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Slide to watch your swing").font(.system(size: 16)).foregroundStyle(Palette.mist)
                Filmstrip(thumbs: an.thumbs, total: an.dets.count, playhead: $an.playhead, events: [:])
            }.card(10)
        }
    }
}
