import SwiftUI

/// A short 3-screen first-run flow: hook → trust → first swing. Shown once.
/// Optimizes for activation (get to the first real swing), not a sale.
struct OnboardingView: View {
    var onDone: () -> Void
    @State private var page = 0
    private let count = 3

    var body: some View {
        ZStack {
            Palette.turf.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { onDone() } label: {
                        Text("Skip").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.mist)
                    }
                }.padding(.horizontal, 20).padding(.top, 10)

                TabView(selection: $page) {
                    slide(glyph: true, title: "A coach in your pocket",
                          body: "See what to fix in your golf swing — in plain words, right here on your phone. No lesson, no jargon.").tag(0)
                    slide(symbol: "figure.golf", title: "It really sees your swing",
                          body: "Swing Check watches your body and your club, then shows you the one thing to work on — drawn right on your own video.").tag(1)
                    slide(symbol: "video.fill", title: "Add your first swing",
                          body: "Film from the front or the side — we figure out which. Or tap “See an example” to try it this second.").tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(0..<count, id: \.self) { i in
                        Circle().fill(i == page ? Palette.fairway : Palette.line).frame(width: 8, height: 8)
                    }
                }.padding(.vertical, 18)

                Button {
                    if page < count - 1 { withAnimation { page += 1 } } else { onDone() }
                } label: {
                    Text(page < count - 1 ? "Continue" : "Let's go").frame(maxWidth: .infinity)
                }
                .buttonStyle(FairwayButton())
                .padding(.horizontal, 20).padding(.bottom, 22)
            }
        }
    }

    @ViewBuilder
    private func slide(glyph: Bool = false, symbol: String? = nil, title: String, body: String) -> some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle().fill(Palette.fairway.opacity(0.12)).frame(width: 156, height: 156)
                if glyph {
                    LogoGlyph(stroke: Palette.fairway, ball: Palette.amber).frame(width: 98, height: 98)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 60)).foregroundStyle(Palette.fairway)
                }
            }
            VStack(spacing: 14) {
                Text(title).font(.display(34)).multilineTextAlignment(.center).foregroundStyle(Palette.chalk)
                Text(body).font(.system(size: 18)).multilineTextAlignment(.center)
                    .foregroundStyle(Palette.mist).lineSpacing(3)
            }.padding(.horizontal, 28)
            Spacer(); Spacer()
        }
    }
}
