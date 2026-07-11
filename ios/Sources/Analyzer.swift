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
    @Published var frameThumbs: [UIImage?] = []   // one cached image per frame — instant scrub
    @Published var playhead: Int = 0              // frame currently being viewed/scrubbed

    func analyze(url: URL) {
        busy = true; progress = 0; frames = []; frameThumbs = []; faults = []
        status = "Analyzing swing…"
        Task {
            do {
                let ex = try await PoseExtractor.extract(url: url) { p in
                    Task { @MainActor in self.progress = p }
                }
                let ev = PoseExtractor.pickEvents(ex.frames)
                self.frames = ex.frames
                self.frameThumbs = ex.thumbs
                self.trackedCount = ex.frames.filter { $0.ok }.count
                guard let ev else {
                    self.busy = false
                    self.status = "We couldn't see you clearly. Stand back so your whole body shows, in good light, and try again."
                    if CommandLine.arguments.contains("-autodemo") { self.writeAutodemoDump(total: ex.frames.count) }
                    return
                }
                self.events = ev
                self.playhead = ev[.address] ?? 0
                self.recompute()
                self.busy = false
                self.status = "All done."
                if CommandLine.arguments.contains("-autodemo") { self.writeAutodemoDump(total: ex.frames.count) }
            } catch {
                self.busy = false
                self.status = "Error: \(error.localizedDescription)"
            }
        }
    }

    func reset() {
        frames = []; events = [:]; faults = []; frameThumbs = []
        selected = .address; playhead = 0; trackedCount = 0; progress = 0; busy = false
        status = "Record or pick a swing video to check."
    }

    func recompute() {
        func pose(_ e: SwingEvent) -> Pose? {
            guard let i = events[e], i >= 0, i < frames.count, frames[i].ok else { return nil }
            return frames[i].pose
        }
        faults = Biomechanics.analyze(address: pose(.address), top: pose(.top), impact: pose(.impact))
    }

    func assign(_ e: SwingEvent, frame: Int) {
        events[e] = frame
        recompute()
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
            Fault(name: "You sway off the ball", value: 0.52, threshold: 0.4,
                  note: "On the backswing your head slides sideways. Try to turn your shoulders instead of sliding off the ball."),
            Fault(name: "You stand up too early", value: 11, threshold: 8,
                  note: "You straighten up as you swing through. Try to stay bent over, in your posture, until after you hit the ball."),
        ]
        status = "Design preview"
        playhead = 3
        if let u = Bundle.main.url(forResource: "demo_swing", withExtension: "mp4") {
            Task.detached {
                let thumbs = (0..<n).map { PoseExtractor.frameImage(url: u, time: Double($0) / Double(n) * 4.6) }
                await MainActor.run { self.frameThumbs = thumbs }
            }
        }
    }
}
