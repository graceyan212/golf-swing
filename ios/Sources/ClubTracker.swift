import Foundation
import CoreML
import Vision
import CoreGraphics

// One frame's club detection. Points are normalized (0..1, y-down).
struct ClubDetection {
    var shaft: CGPoint?
    var clubhead: CGPoint?
    var grip: CGPoint?
    // The shaft vector we care about for plane analysis: grip -> clubhead.
    var shaftLine: (CGPoint, CGPoint)? {
        if let g = grip, let h = clubhead { return (g, h) }
        return nil
    }
    var hasClub: Bool { clubhead != nil && grip != nil }
}

// Runs the on-device YOLO11n club detector (ClubDetector.mlpackage) and decodes its raw
// (1, 7, 8400) head: channels [cx,cy,w,h, shaft, clubhead, grip] per anchor (box in 640px).
// Class indices — 0: shaft, 1: clubhead, 2: grip. Decode verified against the Python export.
final class ClubTracker {
    static let INPUT: CGFloat = 640
    private let model: VNCoreMLModel
    private let conf: Float

    init?(confidence: Float = 0.3) {
        guard let url = Bundle.main.url(forResource: "ClubDetector", withExtension: "mlmodelc"),
              let ml = try? MLModel(contentsOf: url),
              let vn = try? VNCoreMLModel(for: ml) else { return nil }
        self.model = vn
        self.conf = confidence
    }

    func detect(_ cg: CGImage) -> ClubDetection {
        let req = VNCoreMLRequest(model: model)
        req.imageCropAndScaleOption = .scaleFill   // matches the stretched 640x640 resize used at export-check time
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
        guard let obs = req.results?.first as? VNCoreMLFeatureValueObservation,
              let arr = obs.featureValue.multiArrayValue else { return ClubDetection() }
        return decode(arr)
    }

    private func decode(_ m: MLMultiArray) -> ClubDetection {
        guard m.shape.count == 3 else { return ClubDetection() }
        let channels = m.shape[1].intValue          // 7
        let anchors = m.shape[2].intValue           // 8400
        let sC = m.strides[1].intValue
        let sA = m.strides[2].intValue
        let ptr = m.dataPointer.bindMemory(to: Float.self, capacity: m.count)
        @inline(__always) func val(_ c: Int, _ a: Int) -> Float { ptr[c * sC + a * sA] }

        // best (highest-confidence) detection per class index 0/1/2
        var bestConf = [Float](repeating: 0, count: 3)
        var bestPt = [CGPoint?](repeating: nil, count: 3)
        for a in 0..<anchors {
            var cls = 0, best = val(4, a)            // class scores live in channels 4,5,6
            for c in 5..<channels where val(c, a) > best { best = val(c, a); cls = c - 4 }
            if best < conf { continue }
            if best > bestConf[cls] {
                bestConf[cls] = best
                bestPt[cls] = CGPoint(x: CGFloat(val(0, a)) / Self.INPUT,
                                      y: CGFloat(val(1, a)) / Self.INPUT)
            }
        }
        return ClubDetection(shaft: bestPt[0], clubhead: bestPt[1], grip: bestPt[2])
    }
}
