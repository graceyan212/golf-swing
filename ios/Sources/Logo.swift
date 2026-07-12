import SwiftUI

/// The Swing Check mark — a brush checkmark that bounces up into a golf ball at
/// the tip. Same geometry as the app icon. Fits itself to its frame.
struct LogoGlyph: View {
    var stroke: Color
    var ball: Color

    var body: some View {
        Canvas { ctx, size in
            // Mark bounding box in the 0–120 design space (incl. stroke + ball).
            let bx: CGFloat = 20, by: CGFloat = 16.5, bw: CGFloat = 84, bh: CGFloat = 72
            let s = min(size.width / bw, size.height / bh) * 0.98
            let tx = (size.width - bw * s) / 2 - bx * s
            let ty = (size.height - bh * s) / 2 - by * s
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tx + x * s, y: ty + y * s) }

            var p = Path()
            p.move(to: P(25, 74))
            p.addCurve(to: P(42, 73), control1: P(30, 63), control2: P(38, 65))
            p.addCurve(to: P(53, 82), control1: P(46, 80), control2: P(49, 83))
            p.addCurve(to: P(82, 40), control1: P(60, 79), control2: P(66, 60))
            ctx.stroke(p, with: .color(stroke),
                       style: StrokeStyle(lineWidth: 9.5 * s, lineCap: .round, lineJoin: .round))

            let c = P(89, 31), r = 14.5 * s
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(ball))
        }
    }
}

/// The primary logo lockup: mark + wordmark. Used as the app's top brand bar.
struct Wordmark: View {
    var glyph: CGFloat = 40
    var body: some View {
        HStack(spacing: 11) {
            LogoGlyph(stroke: Palette.fairway, ball: Palette.amber)
                .frame(width: glyph, height: glyph)
            Text("Swing Check").font(.display(23)).foregroundStyle(Palette.chalk)
            Spacer(minLength: 0)
        }
    }
}
