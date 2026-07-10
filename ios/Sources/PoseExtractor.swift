import Foundation
import AVFoundation
import Vision
import CoreGraphics
import UIKit

/// Samples frames from a video and runs Apple Vision's on-device body-pose model,
/// mapping joints into our pixel-space Pose. No external dependencies.
enum PoseExtractor {
    static let nSamples = 36
    static let minConfidence: Float = 0.3

    /// Frames + a cached display thumbnail per frame (so scrubbing is instant —
    /// no re-decoding the video from disk on every drag).
    struct Extraction { let frames: [FrameSample]; let thumbs: [UIImage?] }

    static func extract(url: URL, progress: @escaping (Double) -> Void) async throws -> Extraction {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let dur = CMTimeGetSeconds(duration)
        guard dur.isFinite, dur > 0 else {
            throw NSError(domain: "SwingCheck", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "couldn't read the video length"])
        }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero

        var samples: [FrameSample] = []
        var thumbs: [UIImage?] = []
        for i in 0..<nSamples {
            let t = min(dur * (Double(i) + 0.5) / Double(nSamples), max(0, dur - 0.01))
            let time = CMTime(seconds: t, preferredTimescale: 600)
            if let cg = try? gen.copyCGImage(at: time, actualTime: nil) {
                samples.append(detect(upscale(cg, minSide: 512), index: i, time: t))
                thumbs.append(UIImage(cgImage: downscale(cg, maxSide: 480)))
            } else {
                samples.append(FrameSample(index: i, time: t, ok: false, pose: nil, wristHigherY: nil, draw: [:]))
                thumbs.append(nil)
            }
            progress(Double(i + 1) / Double(nSamples))
        }
        return Extraction(frames: samples, thumbs: thumbs)
    }

    private static func downscale(_ img: CGImage, maxSide: CGFloat) -> CGImage {
        let w = CGFloat(img.width), h = CGFloat(img.height)
        let s = min(1.0, maxSide / max(w, h))
        if s >= 1.0 { return img }
        let nw = Int(w * s), nh = Int(h * s)
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage() ?? img
    }

    /// A single frame image for display (unscaled, oriented).
    static func frameImage(url: URL, time: Double) -> UIImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let cm = CMTime(seconds: time, preferredTimescale: 600)
        if let cg = try? gen.copyCGImage(at: cm, actualTime: nil) { return UIImage(cgImage: cg) }
        return nil
    }

    private static func upscale(_ img: CGImage, minSide: CGFloat) -> CGImage {
        let w = CGFloat(img.width), h = CGFloat(img.height)
        let s = max(1.0, minSide / min(w, h))
        if s <= 1.0 { return img }
        let nw = Int(w * s), nh = Int(h * s)
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage() ?? img
    }

    private static func detect(_ img: CGImage, index: Int, time: Double) -> FrameSample {
        let W = Double(img.width), H = Double(img.height)
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: img, orientation: .up, options: [:])
        let empty = FrameSample(index: index, time: time, ok: false, pose: nil, wristHigherY: nil, draw: [:])
        do { try handler.perform([request]) } catch { return empty }
        guard let obs = request.results?.first else { return empty }
        let pts = (try? obs.recognizedPoints(.all)) ?? [:]

        func look(_ name: VNHumanBodyPoseObservation.JointName) -> (Joint, CGPoint)? {
            guard let p = pts[name], p.confidence >= minConfidence else { return nil }
            // Vision: normalized, origin bottom-left, y up -> pixels, y down.
            let px = Double(p.location.x) * W
            let py = (1.0 - Double(p.location.y)) * H
            return (Joint(x: px, y: py), CGPoint(x: p.location.x, y: 1.0 - p.location.y))
        }
        guard let nose = look(.nose), let ls = look(.leftShoulder), let rs = look(.rightShoulder),
              let lh = look(.leftHip), let rh = look(.rightHip) else { return empty }

        let pose = Pose(nose: nose.0, leftShoulder: ls.0, rightShoulder: rs.0, leftHip: lh.0, rightHip: rh.0)
        let lw = look(.leftWrist), rw = look(.rightWrist)
        var wristY: Double? = nil
        if let lw, let rw { wristY = min(lw.0.y, rw.0.y) } else if let lw { wristY = lw.0.y } else if let rw { wristY = rw.0.y }

        let named: [(String, VNHumanBodyPoseObservation.JointName)] = [
            ("nose", .nose), ("lsh", .leftShoulder), ("rsh", .rightShoulder),
            ("lel", .leftElbow), ("rel", .rightElbow), ("lwr", .leftWrist), ("rwr", .rightWrist),
            ("lhip", .leftHip), ("rhip", .rightHip), ("lkn", .leftKnee), ("rkn", .rightKnee),
            ("lan", .leftAnkle), ("ran", .rightAnkle)]
        var draw: [String: CGPoint] = [:]
        for (key, jn) in named { if let v = look(jn) { draw[key] = v.1 } }

        return FrameSample(index: index, time: time, ok: true, pose: pose, wristHigherY: wristY, draw: draw)
    }

    /// Transparent heuristic for Address/Top/Impact (user adjusts with sliders).
    static func pickEvents(_ frames: [FrameSample]) -> [SwingEvent: Int]? {
        let ok = frames.filter { $0.ok }
        guard ok.count >= 3 else { return nil }
        let n = frames.count
        let address = ok.first(where: { $0.index <= Int(Double(n) * 0.2) }) ?? ok.first!
        let ai = address.index

        var top: FrameSample? = nil
        for f in ok where f.index > ai && f.index <= Int(Double(n) * 0.7) {
            guard let cy = f.wristHigherY else { continue }
            if top == nil || (top!.wristHigherY ?? .infinity) > cy { top = f }
        }
        let topFrame = top ?? ok[ok.count / 2]
        let ti = topFrame.index

        let addrHandY = address.wristHigherY ?? address.pose?.nose.y ?? 0
        var impact: FrameSample? = nil
        var best = Double.infinity
        for f in ok where f.index > ti {
            let hy = f.wristHigherY ?? f.pose?.nose.y ?? 0
            let d = abs(hy - addrHandY)
            if d < best { best = d; impact = f }
        }
        let impactFrame = impact ?? ok.last!
        return [.address: ai, .top: ti, .impact: impactFrame.index]
    }
}
