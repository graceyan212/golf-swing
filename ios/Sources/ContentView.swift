import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Lets PhotosPicker hand us a playable file URL for the chosen video.
struct Movie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent("swing-\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return Movie(url: dst)
        }
    }
}

struct ContentView: View {
    @StateObject private var analyzer = Analyzer()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    static let bones: [(String, String)] = [
        ("lsh", "rsh"), ("lsh", "lhip"), ("rsh", "rhip"), ("lhip", "rhip"),
        ("lsh", "lel"), ("lel", "lwr"), ("rsh", "rel"), ("rel", "rwr"),
        ("lhip", "lkn"), ("lkn", "lan"), ("rhip", "rkn"), ("rkn", "ran"),
        ("nose", "lsh"), ("nose", "rsh")]

    private var hasResult: Bool { !analyzer.frames.isEmpty && !analyzer.events.isEmpty }

    var body: some View {
        ZStack {
            Palette.turf.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if analyzer.busy { analyzingCard }
                    if hasResult { results } else if !analyzer.busy { emptyState }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Palette.fairway)
        .onChange(of: pickerItem) { _, item in loadPicked(item) }
        .fullScreenCover(isPresented: $showCamera) {
            CameraRecorder { url in analyzer.analyze(url: url) }.ignoresSafeArea()
        }
        .onAppear {
            if CommandLine.arguments.contains("-uidemo") { analyzer.loadUIDemo() }
            else if CommandLine.arguments.contains("-autodemo") { runDemo() }
        }
    }

    // MARK: header
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow("Swing Lab")
                Text("Swing Check").font(.display(30)).foregroundStyle(Palette.chalk)
            }
            Spacer()
            SwingArc().frame(width: 46, height: 46)
        }
    }

    // MARK: empty state
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Read your swing.").font(.display(38)).foregroundStyle(Palette.chalk)
                Text("Record a face-on swing. Get your key positions and what to fix — computed on your phone.")
                    .font(.system(size: 16)).foregroundStyle(Palette.mist)
            }
            SwingArcHero().frame(height: 168).card(0)
            actionButtons
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("For a clean read")
                ForEach(["Film face-on (camera facing you)", "Fit your whole body in frame",
                         "Hold the phone steady", "Trim to just the swing"], id: \.self) { t in
                    HStack(spacing: 10) {
                        Circle().fill(Palette.fairway).frame(width: 5, height: 5)
                        Text(t).font(.system(size: 14)).foregroundStyle(Palette.mist)
                    }
                }
            }.card()
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                if cameraAvailable { showCamera = true }
            } label: {
                Label("Record a swing", systemImage: "video.fill")
            }
            .buttonStyle(FairwayButton())
            .disabled(!cameraAvailable)

            if !cameraAvailable {
                Text("Recording needs a real device — in the Simulator, use “Choose from library” or the demo clip.")
                    .font(.system(size: 12)).foregroundStyle(Palette.mist)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }

            PhotosPicker(selection: $pickerItem, matching: .videos) {
                Label("Choose from library", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(GhostButton())

            if Bundle.main.url(forResource: "demo_swing", withExtension: "mp4") != nil {
                Button { runDemo() } label: { Label("Try the demo clip", systemImage: "play.circle") }
                    .buttonStyle(GhostButton())
            }
        }
    }

    private var analyzingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Analyzing", color: Palette.fairway)
            Text(analyzer.status).font(.system(size: 15)).foregroundStyle(Palette.chalk)
            ProgressView(value: analyzer.progress).tint(Palette.fairway)
        }.card()
    }

    // MARK: results
    private var results: some View {
        VStack(alignment: .leading, spacing: 18) {
            verdictHero
            scrubCard
            diagnosis
            Button { analyzer.reset() } label: { Label("Analyze another swing", systemImage: "arrow.counterclockwise") }
                .buttonStyle(GhostButton())
        }
    }

    private var faultColor: Color { analyzer.faults.isEmpty ? Palette.fairway : Palette.flag }

    private var verdictHero: some View {
        HStack(alignment: .center, spacing: 16) {
            if analyzer.faults.isEmpty {
                ZStack {
                    Circle().fill(Palette.fairway.opacity(0.16)).frame(width: 66, height: 66)
                    Image(systemName: "checkmark").font(.system(size: 28, weight: .heavy)).foregroundStyle(Palette.fairway)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow("Swing report")
                    Text("Clean swing").font(.display(28)).foregroundStyle(Palette.chalk)
                    Text("Sway, hip slide and extension all in range").font(.system(size: 13)).foregroundStyle(Palette.mist)
                }
            } else {
                Text("\(analyzer.faults.count)").font(.display(66)).monospacedDigit().foregroundStyle(faultColor)
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow("Swing report")
                    Text(analyzer.faults.count == 1 ? "fault to fix" : "faults to fix")
                        .font(.display(23)).foregroundStyle(Palette.chalk)
                    Text(analyzer.faults.map { $0.name.capitalized }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(Palette.mist).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }.card()
    }

    // MARK: scrub card (Photos-style frame-by-frame)
    private var currentThumb: UIImage? {
        let p = analyzer.playhead
        return p >= 0 && p < analyzer.frameThumbs.count ? analyzer.frameThumbs[p] : nil
    }
    private var currentPlayFrame: FrameSample? {
        let p = analyzer.playhead
        return p >= 0 && p < analyzer.frames.count ? analyzer.frames[p] : nil
    }
    private var currentAssignment: String? {
        let hits = SwingEvent.allCases.filter { analyzer.events[$0] == analyzer.playhead }
        return hits.isEmpty ? nil : hits.map { $0.rawValue }.joined(separator: " · ")
    }

    private var scrubCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                SwingCanvas(image: currentThumb, frame: currentPlayFrame)
                HStack(spacing: 6) {
                    Circle().fill(Palette.fairway).frame(width: 6, height: 6)
                    Text("POSE").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(Palette.chalk)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule()).padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Eyebrow("Frame \(analyzer.playhead + 1) / \(max(1, analyzer.frames.count))")
                Spacer()
                if let a = currentAssignment { Eyebrow(a, color: Palette.fairway) }
            }

            Filmstrip(thumbs: analyzer.frameThumbs, total: analyzer.frames.count,
                      playhead: $analyzer.playhead, events: analyzer.events)

            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("Set this frame as")
                HStack(spacing: 8) { ForEach(SwingEvent.allCases) { setButton($0) } }
            }
        }.card(10)
    }

    private func setButton(_ e: SwingEvent) -> some View {
        let here = analyzer.events[e] == analyzer.playhead
        return Button { analyzer.assign(e, frame: analyzer.playhead) } label: {
            Text(e.rawValue).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(here ? Palette.turf : Palette.chalk)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(here ? Palette.fairway : Palette.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(here ? Color.clear : Palette.line, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private var diagnosis: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Diagnosis")
            if analyzer.faults.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.fairway)
                    Text("No major faults — sway, hip slide and early extension are all within range.")
                        .font(.system(size: 14)).foregroundStyle(Palette.chalk)
                }.card()
            } else {
                ForEach(analyzer.faults) { FaultCard(fault: $0) }
            }
        }
    }

    // MARK: actions
    private func loadPicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let movie = try? await item.loadTransferable(type: Movie.self) { analyzer.analyze(url: movie.url) }
            else { analyzer.status = "Couldn't load that video." }
        }
    }
    private func runDemo() {
        if let u = Bundle.main.url(forResource: "demo_swing", withExtension: "mp4") { analyzer.analyze(url: u) }
    }
}

// MARK: - Swing pose canvas
struct SwingCanvas: View {
    let image: UIImage?
    let frame: FrameSample?
    var body: some View {
        let aspect = image?.size ?? CGSize(width: 3, height: 4)
        Canvas { ctx, size in
            if let image {
                ctx.draw(ctx.resolve(Image(uiImage: image)), in: CGRect(origin: .zero, size: size))
            } else {
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.surface2))
            }
            guard let f = frame, f.ok, !f.draw.isEmpty else { return }
            if let lh = f.draw["lhip"], let rh = f.draw["rhip"] {
                let cx = (lh.x + rh.x) / 2 * size.width
                var c = Path(); c.move(to: CGPoint(x: cx, y: 0)); c.addLine(to: CGPoint(x: cx, y: size.height))
                ctx.stroke(c, with: .color(Palette.chalk.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
            }
            for (a, b) in ContentView.bones {
                if let pa = f.draw[a], let pb = f.draw[b] {
                    var p = Path()
                    p.move(to: CGPoint(x: pa.x * size.width, y: pa.y * size.height))
                    p.addLine(to: CGPoint(x: pb.x * size.width, y: pb.y * size.height))
                    ctx.stroke(p, with: .color(Palette.fairway), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
            for (_, pt) in f.draw {
                let r = CGRect(x: pt.x * size.width - 4, y: pt.y * size.height - 4, width: 8, height: 8)
                ctx.fill(Path(ellipseIn: r), with: .color(Palette.chalk))
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .background(Color.black)
    }
}

// MARK: - Signature: filmstrip scrubber (Photos-style frame-by-frame)
struct Filmstrip: View {
    let thumbs: [UIImage?]
    let total: Int
    @Binding var playhead: Int
    let events: [SwingEvent: Int]

    private func frac(_ i: Int) -> CGFloat { total > 1 ? CGFloat(i) / CGFloat(total - 1) : 0 }
    private func tint(_ e: SwingEvent) -> Color {
        switch e { case .address: return Palette.chalk; case .top: return Palette.fairway; case .impact: return Palette.amber }
    }
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let n = min(14, max(1, thumbs.count))
            ZStack(alignment: .topLeading) {
                HStack(spacing: 1) {
                    ForEach(Array(0..<n), id: \.self) { k in
                        let idx = thumbs.count > 1 ? Int((Double(k) / Double(max(1, n - 1))) * Double(thumbs.count - 1)) : 0
                        Group {
                            if idx < thumbs.count, let img = thumbs[idx] {
                                Image(uiImage: img).resizable().scaledToFill()
                            } else { Palette.surface2 }
                        }
                        .frame(width: (w - CGFloat(n - 1)) / CGFloat(n), height: h).clipped()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Palette.line, lineWidth: 1))

                ForEach(SwingEvent.allCases) { e in
                    if let i = events[e] {
                        tint(e).frame(width: 2.5, height: h).offset(x: frac(i) * (w - 2.5))
                    }
                }
                RoundedRectangle(cornerRadius: 2).fill(Palette.chalk)
                    .frame(width: 3, height: h + 10).offset(x: frac(playhead) * (w - 3), y: -5)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let f = min(max(0, v.location.x / w), 1)
                playhead = Int((f * Double(max(1, total - 1))).rounded())
            })
        }
        .frame(height: 56)
    }
}

// MARK: - Fault card
struct FaultCard: View {
    let fault: Fault
    private var valueUnit: (String, String) {
        if fault.name.contains("extension") { return ("\(Int(fault.value))°", "spine straightening") }
        return (String(format: "%+.2f", fault.value), "shoulder-widths")
    }
    private var coaching: String { fault.note.components(separatedBy: "— ").last ?? fault.note }
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 2).fill(Palette.flag).frame(width: 4)
            VStack(alignment: .leading, spacing: 7) {
                Eyebrow(fault.name, color: Palette.flag)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(valueUnit.0).font(.readout(30, .bold)).foregroundStyle(Palette.chalk)
                    Text(valueUnit.1).font(.system(size: 12)).foregroundStyle(Palette.mist)
                }
                Text(coaching).font(.system(size: 14)).foregroundStyle(Palette.mist).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }
}

// MARK: - Small swing-arc glyph (header)
struct SwingArc: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var arc = Path()
            arc.move(to: CGPoint(x: w * 0.18, y: h * 0.86))
            arc.addQuadCurve(to: CGPoint(x: w * 0.82, y: h * 0.30), control: CGPoint(x: w * 0.16, y: h * 0.10))
            ctx.stroke(arc, with: .color(Palette.fairway), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.82 - 4, y: h * 0.30 - 4, width: 8, height: 8)), with: .color(Palette.amber))
        }
    }
}

// MARK: - Empty-state ambient arc
struct SwingArcHero: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var ground = Path(); ground.move(to: CGPoint(x: 20, y: h - 22)); ground.addLine(to: CGPoint(x: w - 20, y: h - 22))
            ctx.stroke(ground, with: .color(Palette.line), lineWidth: 1)
            let A = CGPoint(x: w * 0.26, y: h - 30), T = CGPoint(x: w * 0.72, y: 26), I = CGPoint(x: w * 0.50, y: h - 30)
            var arc = Path(); arc.move(to: A)
            arc.addQuadCurve(to: T, control: CGPoint(x: w * 0.30, y: 18))
            arc.addQuadCurve(to: I, control: CGPoint(x: w * 0.92, y: h * 0.55))
            ctx.stroke(arc, with: .color(Palette.fairway.opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            for (p, lab, c) in [(A, "A", Palette.chalk), (T, "T", Palette.fairway), (I, "I", Palette.amber)] {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(c))
                ctx.draw(Text(lab).font(.readout(11, .bold)).foregroundColor(Palette.mist), at: CGPoint(x: p.x, y: p.y - 17))
            }
        }
    }
}
