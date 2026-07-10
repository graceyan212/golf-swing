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
            Button { showCamera = true } label: {
                Label("Record a swing", systemImage: "video.fill")
            }
            .buttonStyle(FairwayButton())
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

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
            videoCard
            positionControl
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

    private var currentFrame: FrameSample? {
        guard let i = analyzer.events[analyzer.selected], i < analyzer.frames.count else { return nil }
        return analyzer.frames[i]
    }

    private var videoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                SwingCanvas(image: analyzer.eventImages[analyzer.selected], frame: currentFrame)
                HStack(spacing: 6) {
                    Circle().fill(Palette.fairway).frame(width: 6, height: 6)
                    Text("POSE").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(Palette.chalk)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(captionForSelected).font(.system(size: 13)).foregroundStyle(Palette.mist)
        }.card(10)
    }

    private var captionForSelected: String {
        let e = analyzer.selected
        if let f = currentFrame, !f.ok { return "\(e.rawValue) — no body detected here; drag to a frame where you're in view." }
        return "\(e.rawValue) position"
    }

    private var positionControl: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Key positions")
            HStack(spacing: 8) {
                ForEach(SwingEvent.allCases) { e in
                    let on = analyzer.selected == e
                    Button { analyzer.selected = e } label: {
                        Text(e.rawValue).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(on ? Palette.turf : Palette.chalk)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(on ? Palette.fairway : Palette.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
            TempoTrack(total: analyzer.frames.count, events: analyzer.events, selected: $analyzer.selected)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Eyebrow("\(analyzer.selected.rawValue) · frame \((analyzer.events[analyzer.selected] ?? 0) + 1)/\(analyzer.frames.count)")
                    Spacer()
                    Text("drag to fine-tune").font(.system(size: 11)).foregroundStyle(Palette.mist)
                }
                Slider(value: Binding(
                    get: { Double(analyzer.events[analyzer.selected] ?? 0) },
                    set: { analyzer.setEvent(analyzer.selected, index: Int($0.rounded())) }),
                    in: 0...Double(max(1, analyzer.frames.count - 1)), step: 1)
            }
        }.card()
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
            // faint center reference line through mid-hip ("stay centered")
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

// MARK: - Signature: swing-tempo timeline
struct TempoTrack: View {
    let total: Int
    let events: [SwingEvent: Int]
    @Binding var selected: SwingEvent
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, midY = geo.size.height / 2
            ZStack {
                Capsule().fill(Palette.surface2).frame(height: 4).padding(.horizontal, 12)
                ForEach(SwingEvent.allCases) { e in
                    let idx = events[e] ?? 0
                    let frac = total > 1 ? CGFloat(idx) / CGFloat(total - 1) : 0
                    let x = 12 + frac * (w - 24)
                    let on = selected == e
                    Circle()
                        .fill(on ? Palette.fairway : Palette.surface2)
                        .overlay(Circle().stroke(on ? Palette.fairway : Palette.line, lineWidth: 1.5))
                        .frame(width: on ? 16 : 12, height: on ? 16 : 12)
                        .overlay(Text(String(e.rawValue.prefix(1)))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(on ? Palette.fairway : Palette.mist)
                            .offset(y: -19))
                        .position(x: x, y: midY)
                        .onTapGesture { selected = e }
                }
            }
        }
        .frame(height: 44)
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
