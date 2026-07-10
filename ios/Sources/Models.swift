import Foundation
import CoreGraphics

/// A 2D joint in image PIXELS (x right, y down) — matches swing/biomechanics.py.
struct Joint {
    var x: Double
    var y: Double
}

/// The five joints the fault layer needs.
struct Pose {
    var nose: Joint
    var leftShoulder: Joint
    var rightShoulder: Joint
    var leftHip: Joint
    var rightHip: Joint
}

/// One sampled frame of the video.
struct FrameSample {
    let index: Int
    let time: Double
    let ok: Bool
    let pose: Pose?
    let wristHigherY: Double?          // higher wrist pixel-y (min y); used by the event heuristic
    let draw: [String: CGPoint]        // normalized (x right, y down) points for the overlay
}

struct Fault: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let threshold: Double
    let note: String
}

enum SwingEvent: String, CaseIterable, Identifiable {
    case address = "Address"
    case top = "Top"
    case impact = "Impact"
    var id: String { rawValue }
}
