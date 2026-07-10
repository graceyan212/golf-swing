import SwiftUI

// "Swing-lab" identity: twilight-turf base, chalk text, and a semantic 3-color
// system (fairway = clean, amber = minor, flag = fault) where every color means
// one thing. Measurements are set in monospaced digits like a launch-monitor readout.
extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Palette {
    static let turf     = Color(hex: 0x0C120E)   // background — twilight range, not pure black
    static let surface  = Color(hex: 0x141C17)   // cards
    static let surface2 = Color(hex: 0x1C261F)   // raised chips / tracks
    static let line     = Color(hex: 0x27322B)   // hairlines
    static let chalk    = Color(hex: 0xEDF3EE)   // primary text
    static let mist     = Color(hex: 0x8CA396)   // secondary text
    static let fairway  = Color(hex: 0x34C06B)   // GOOD / clean / primary action
    static let amber    = Color(hex: 0xF2B84B)   // minor
    static let flag     = Color(hex: 0xFF6B57)   // fault
}

extension Font {
    static func display(_ size: CGFloat, _ w: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: w, design: .rounded)
    }
    static func readout(_ size: CGFloat, _ w: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: w, design: .monospaced)
    }
}

// Uppercase, tracked instrument label.
struct Eyebrow: View {
    let text: String
    var color: Color = Palette.mist
    init(_ text: String, color: Color = Palette.mist) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(color)
    }
}

struct CardBG: ViewModifier {
    var pad: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }
}
extension View {
    func card(_ pad: CGFloat = 18) -> some View { modifier(CardBG(pad: pad)) }
}

// Filled fairway primary action.
struct FairwayButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Palette.turf)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Palette.fairway.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

// Quiet outlined secondary action.
struct GhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Palette.chalk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Palette.surface2.opacity(configuration.isPressed ? 0.6 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }
}
