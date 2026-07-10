import SwiftUI
import UIKit

@MainActor
final class Analyzer: ObservableObject {
    @Published var status = "Pick or record a face-on swing video to analyze."
    @Published var busy = false
    @Published var progress: Double = 0
    @Published var frames: [FrameSample] = []
    @Published var events: [SwingEvent: Int] = [:]
    @Published var selected: SwingEvent = .address
    @Published var faults: [Fault] = []
    @Published var trackedCount = 0
    @Published var eventImages: [SwingEvent: UIImage] = [:]

    private var url: URL?

    func analyze(url: URL) {
        self.url = url
        busy = true; progress = 0; frames = []; faults = []; eventImages = [:]
        status = "Analyzing swing…"
        Task {
            do {
                let fs = try await PoseExtractor.extract(url: url) { p in
                    Task { @MainActor in self.progress = p }
                }
                let ev = PoseExtractor.pickEvents(fs)
                self.frames = fs
                self.trackedCount = fs.filter { $0.ok }.count
                guard let ev else {
                    self.busy = false
                    self.status = "Couldn't track your body — film face-on, full body in frame, good light, trimmed to the swing."
                    if CommandLine.arguments.contains("-autodemo") { self.writeAutodemoDump(total: fs.count) }
                    return
                }
                self.events = ev
                self.recompute()
                await self.renderEventImages()
                self.busy = false
                self.status = "Done — \(self.trackedCount)/\(fs.count) frames tracked. Auto-detected positions are approximate; drag a slider to fix any."
                if CommandLine.arguments.contains("-autodemo") { self.writeAutodemoDump(total: fs.count) }
            } catch {
                self.busy = false
                self.status = "Error: \(error.localizedDescription)"
            }
        }
    }

    func reset() {
        frames = []; events = [:]; faults = []; eventImages = [:]
        selected = .address; trackedCount = 0; progress = 0; busy = false
        status = "Pick or record a face-on swing video to analyze."
    }

    func recompute() {
        func pose(_ e: SwingEvent) -> Pose? {
            guard let i = events[e], i >= 0, i < frames.count, frames[i].ok else { return nil }
            return frames[i].pose
        }
        faults = Biomechanics.analyze(address: pose(.address), top: pose(.top), impact: pose(.impact))
    }

    func setEvent(_ e: SwingEvent, index: Int) {
        events[e] = index
        recompute()
        Task { await renderOne(e) }
    }

    /// Verification hook: on `-autodemo`, dump the computed result to the app's
    /// Documents dir so the build harness can read what the pipeline actually produced.
    private func writeAutodemoDump(total: Int) {
        var lines: [String] = []
        lines.append("tracked=\(trackedCount)/\(total)")
        lines.append("events=" + SwingEvent.allCases.map { "\($0.rawValue):\(events[$0] ?? -1)" }.joined(separator: ","))
        if faults.isEmpty {
            lines.append("faults=NONE (clean)")
        } else {
            for f in faults { lines.append("fault: \(f.name) value=\(f.value) thr=\(f.threshold) :: \(f.note)") }
        }
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("autodemo_result.txt"),
                                                      atomically: true, encoding: .utf8)
        }
    }

    // Design-preview only (launch arg -uidemo): populate a realistic result so the
    // redesigned UI can be reviewed where on-device Vision isn't available (Simulator).
    func loadUIDemo() {
        let n = 48
        frames = (0..<n).map { FrameSample(index: $0, time: Double($0) / Double(n) * 4.6, ok: true, pose: nil, wristHigherY: nil, draw: [:]) }
        events = [.address: 3, .top: 24, .impact: 33]
        trackedCount = n
        faults = [
            Fault(name: "sway off ball", value: 0.52, threshold: 0.4,
                  note: "head slides +0.52 shoulder-widths on the backswing (steady is within ±0.4) — you're swaying off the ball instead of turning"),
            Fault(name: "early extension", value: 11, threshold: 8,
                  note: "spine straightens 11° from address to impact (>8.0) — early extension / standing up through the shot"),
        ]
        status = "Design preview"
        if let u = Bundle.main.url(forResource: "demo_swing", withExtension: "mp4") {
            for (e, idx) in events {
                if let img = PoseExtractor.frameImage(url: u, time: Double(idx) / Double(n) * 4.6) { eventImages[e] = img }
            }
        }
    }

    func renderEventImages() async {
        for e in SwingEvent.allCases { await renderOne(e) }
    }

    func renderOne(_ e: SwingEvent) async {
        guard let url, let i = events[e], i >= 0, i < frames.count else { return }
        let t = frames[i].time
        let img = await Task.detached { PoseExtractor.frameImage(url: url, time: t) }.value
        if let img { eventImages[e] = img }
    }
}
