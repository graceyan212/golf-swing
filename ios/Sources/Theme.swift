import SwiftUI

// "Fairway Heritage" identity: warm parchment, pine green, clay, brass — a premium,
// high-contrast, country-club read for an older golfer. TWO fonts only, one rule:
// a serif (New York) for headings & verdicts; a sans (SF Pro) for everything else,
// with tabular figures for numbers. (Token names kept so every screen inherits this.)
extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Palette {
    static let turf     = Color(hex: 0xEFE7D4)   // background — parchment
    static let surface  = Color(hex: 0xFAF5E9)   // cards
    static let surface2 = Color(hex: 0xF1EAD9)   // raised chips / tracks
    static let line     = Color(hex: 0xDCCFB0)   // hairlines
    static let chalk    = Color(hex: 0x20261F)   // primary text (ink)
    static let mist     = Color(hex: 0x6F6A58)   // secondary text (muted)
    static let fairway  = Color(hex: 0x1F5138)   // pine — GOOD / clean / primary action
    static let amber    = Color(hex: 0xB4893C)   // brass — minor
    static let flag     = Color(hex: 0xA83C2B)   // clay — fault
}

extension Font {
    // Headings & verdicts — serif (New York on iOS).
    static func display(_ size: CGFloat, _ w: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: w, design: .serif)
    }
    // Numbers — sans (SF Pro) with tabular figures, so stats align. No monospace font.
    static func readout(_ size: CGFloat, _ w: Font.Weight = .bold) -> Font {
        .system(size: size, weight: w).monospacedDigit()
    }
}

// Uppercase, tracked label — sans.
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

// Filled pine primary action (parchment text; dims clearly when disabled).
struct FairwayButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { FairwayButtonBody(configuration: configuration) }
}
private struct FairwayButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Palette.turf)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Palette.fairway.opacity(!enabled ? 0.4 : (configuration.isPressed ? 0.82 : 1)))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .opacity(enabled ? 1 : 0.7)
    }
}

// Quiet outlined secondary action.
struct GhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { GhostButtonBody(configuration: configuration) }
}
private struct GhostButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Palette.chalk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Palette.surface2.opacity(configuration.isPressed ? 0.6 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Palette.line, lineWidth: 1))
            .opacity(enabled ? 1 : 0.6)
    }
}
