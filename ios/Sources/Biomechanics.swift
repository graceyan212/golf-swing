import Foundation

/// Swift port of swing/biomechanics.py — kept in lockstep (verified identical by the
/// JS parity test in app/, and the same constants/geometry here).
enum Biomechanics {
    static let swayThresh = 0.40
    static let slideThresh = 0.70
    static let earlyExtThresh = 8.0

    static func mid(_ a: Joint, _ b: Joint) -> Joint { Joint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    static func dist(_ a: Joint, _ b: Joint) -> Double { hypot(a.x - b.x, a.y - b.y) }
    static func midShoulder(_ p: Pose) -> Joint { mid(p.leftShoulder, p.rightShoulder) }
    static func midHip(_ p: Pose) -> Joint { mid(p.leftHip, p.rightHip) }
    static func shoulderWidth(_ p: Pose) -> Double { max(dist(p.leftShoulder, p.rightShoulder), 1e-6) }

    /// Lateral spine tilt (deg from vertical): angle of the hip->shoulder line.
    static func spineTilt(_ p: Pose) -> Double {
        let ms = midShoulder(p), mh = midHip(p)
        return atan2(abs(ms.x - mh.x), abs(ms.y - mh.y)) * 180 / .pi
    }

    /// Signed horizontal shift in shoulder-widths (+ = toward image-right).
    static func lat(_ ref: Joint, _ now: Joint, _ sw: Double) -> Double { (now.x - ref.x) / sw }

    private static func r2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
    private static func r1(_ x: Double) -> Double { (x * 10).rounded() / 10 }

    static func analyze(address A: Pose?, top T: Pose?, impact I: Pose?) -> [Fault] {
        var faults: [Fault] = []
        if let A, let T {
            let sway = lat(A.nose, T.nose, shoulderWidth(A))
            if abs(sway) > swayThresh {
                faults.append(Fault(
                    name: "You sway off the ball", value: r2(sway), threshold: swayThresh,
                    note: "On the backswing your head slides sideways. Try to turn your shoulders instead of sliding off the ball."))
            }
        }
        if let A, let I {
            let slide = lat(midHip(A), midHip(I), shoulderWidth(A))
            if abs(slide) > slideThresh {
                faults.append(Fault(
                    name: "Your hips slide", value: r2(slide), threshold: slideThresh,
                    note: "Your hips push toward the target instead of turning. Try to rotate your hips around, not slide them."))
            }
            let drop = spineTilt(A) - spineTilt(I)   // + = spine straightened toward vertical
            if drop > earlyExtThresh {
                faults.append(Fault(
                    name: "You stand up too early", value: r1(drop), threshold: earlyExtThresh,
                    note: "You straighten up as you swing through. Try to stay bent over, in your posture, until after you hit the ball."))
            }
        }
        return faults
    }
}
