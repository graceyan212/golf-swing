import Foundation
import AVFoundation
import Vision
import CoreGraphics

/// Auto-detects whether a swing was filmed from the FRONT (face-on) or the SIDE
/// (down-the-line), using the body-pose model we already run. Tell: face-on the
/// shoulders/hips look wide; side-on the golfer is turned so one side hides the
/// other, making shoulder/hip width small next to torso height.
enum OrientationDetector {
    /// Returns true if the video looks like a SIDE (down-the-line) view.
    static func looksLikeSide(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let dur = (try? await asset.load(.duration)).map(CMTimeGetSeconds), dur > 0 else { return false }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero

        var ratios: [Double] = []
        let n = 12
        for i in 0..<n {
            let t = min(dur * (Double(i) + 0.5) / Double(n), max(0, dur - 0.01))
            guard let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) else { continue }
            if let r = widthOverHeight(cg) { ratios.append(r) }
        }
        guard ratios.count >= 3 else { return false }   // not enough signal → assume front
        ratios.sort()
        let median = ratios[ratios.count / 2]
        // face-on ≈ 0.5–1.0 ; down-the-line ≈ 0.05–0.35. Split at 0.42.
        return median < 0.42
    }

    /// (shoulder+hip breadth) / torso height, in pixels (aspect-independent). nil if pose not found.
    private static func widthOverHeight(_ img: CGImage) -> Double? {
        let W = Double(img.width), H = Double(img.height)
        let req = VNDetectHumanBodyPoseRequest()
        do { try VNImageRequestHandler(cgImage: img, orientation: .up, options: [:]).perform([req]) }
        catch { return nil }
        guard let obs = req.results?.first, let pts = try? obs.recognizedPoints(.all) else { return nil }
        func pt(_ j: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = pts[j], p.confidence >= 0.2 else { return nil }
            return CGPoint(x: Double(p.location.x) * W, y: (1 - Double(p.location.y)) * H)
        }
        guard let ls = pt(.leftShoulder), let rs = pt(.rightShoulder),
              let lh = pt(.leftHip), let rh = pt(.rightHip) else { return nil }
        let shoulderW = abs(ls.x - rs.x)
        let hipW = abs(lh.x - rh.x)
        let midSh = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
        let midHip = CGPoint(x: (lh.x + rh.x) / 2, y: (lh.y + rh.y) / 2)
        let torsoH = max(abs(midSh.y - midHip.y), 1)
        return Double((shoulderW + hipW) / 2 / torsoH)
    }
}
