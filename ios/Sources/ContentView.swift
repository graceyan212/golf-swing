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
    enum Shot { case front, side }

    @StateObject private var analyzer = Analyzer()
    @StateObject private var plane = PlaneAnalyzer()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var videoURL: URL?      // the video the user added
    @State private var shot: Shot?         // front/side, auto-detected after the video is added
    @State private var detecting = false   // running the front/side auto-detect
    @State private var adjusting = false   // manually moving Address/Top/Impact

    static let bones: [(String, String)] = [
        ("lsh", "rsh"), ("lsh", "lhip"), ("rsh", "rhip"), ("lhip", "rhip"),
        ("lsh", "lel"), ("lel", "lwr"), ("rsh", "rel"), ("rel", "rwr"),
        ("lhip", "lkn"), ("lkn", "lan"), ("rhip", "rkn"), ("rkn", "ran"),
        ("nose", "lsh"), ("nose", "rsh")]

    private var hasFrontResult: Bool { !analyzer.frames.isEmpty && !analyzer.events.isEmpty }
    private var hasSideResult: Bool { !plane.dets.isEmpty && plane.playhead < plane.dets.count }

    var body: some View {
        ZStack {
            Palette.turf.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if detecting {
                        busyCard(nil)
                    } else {
                        switch shot {
                        case .front:
                            if analyzer.busy { busyCard(analyzer.progress) }
                            else if hasFrontResult { frontResults } else { landing }
                        case .side:
                            if plane.busy { busyCard(plane.progress) }
                            else if hasSideResult { sideResults } else { landing }
                        case nil:
                            landing
                        }
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.light)
        .tint(Palette.fairway)
        .onChange(of: pickerItem) { _, item in loadPicked(item) }
        .fullScreenCover(isPresented: $showCamera) {
            CameraRecorder { url in addVideo(url) }.ignoresSafeArea()
        }
        .onAppear {
            if CommandLine.arguments.contains("-uidemo") { analyzer.loadUIDemo(); shot = .front }
            else if CommandLine.arguments.contains("-autodemo"), let u = demoURL { videoURL = u; shot = .front; analyzer.analyze(url: u) }
            else if CommandLine.arguments.contains("-dtldemo"), let u = demoURL { videoURL = u; shot = .side; plane.analyze(url: u) }
            else if CommandLine.arguments.contains("-detectdemo"), let u = demoURL { addVideo(u) }
        }
    }

    private var demoURL: URL? { Bundle.main.url(forResource: "demo_swing", withExtension: "mp4") }

    // MARK: header — the logo (mark + small wordmark), a brand bar above the hero
    private var header: some View {
        Wordmark(glyph: 42).padding(.bottom, 2)
    }

    // MARK: landing — one place to add a video
    private var landing: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Check your swing").font(.display(40)).foregroundStyle(Palette.chalk)
                Text("Add a video of your golf swing. We'll show you what to fix, in plain words.")
                    .font(.system(size: 19)).foregroundStyle(Palette.mist).lineSpacing(3)
            }
            actionButtons
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.fill").font(.system(size: 18)).foregroundStyle(Palette.amber)
                Text("Stand back so your whole body shows, and hold the phone still. Front or side — we'll figure out which.")
                    .font(.system(size: 17)).foregroundStyle(Palette.chalk).lineSpacing(2)
            }.card()
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                if cameraAvailable { showCamera = true }
            } label: {
                Label("Record my swing", systemImage: "video.fill")
            }
            .buttonStyle(FairwayButton())
            .disabled(!cameraAvailable)

            if !cameraAvailable {
                Text("To record, open this on your iPhone. For now, pick a saved video or see an example.")
                    .font(.system(size: 14)).foregroundStyle(Palette.mist)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }

            PhotosPicker(selection: $pickerItem, matching: .videos) {
                Label("Pick a saved video", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(GhostButton())

            if demoURL != nil {
                Button { if let u = demoURL { addVideo(u) } } label: { Label("See an example", systemImage: "play.circle") }
                    .buttonStyle(GhostButton())
            }
        }
    }

    // Shown while detecting front/side (progress == nil) or analyzing (progress set).
    private func busyCard(_ progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(progress == nil ? "Getting your video ready…" : "Looking at your swing…")
                .font(.display(22)).foregroundStyle(Palette.chalk)
            if let p = progress { ProgressView(value: p).tint(Palette.fairway) }
            else { ProgressView().tint(Palette.fairway) }
        }.card()
    }

    // MARK: results — front (face-on) view
    private var frontResults: some View {
        VStack(alignment: .leading, spacing: 18) {
            verdictHero
            swingCard
            diagnosis
            correctionLink(current: "front")
            Button { resetAll() } label: { Label("Check another swing", systemImage: "arrow.counterclockwise") }
                .buttonStyle(GhostButton())
        }
    }

    // MARK: results — side (down-the-line) view
    private var sideResults: some View {
        VStack(alignment: .leading, spacing: 18) {
            PlaneResultsView(an: plane)
            correctionLink(current: "side")
            Button { resetAll() } label: { Label("Check another swing", systemImage: "arrow.counterclockwise") }
                .buttonStyle(GhostButton())
        }
    }

    // "We guessed this was a front/side video — wrong? switch" — one tap to re-read the same video.
    private func correctionLink(current: String) -> some View {
        HStack(spacing: 4) {
            Text(current == "front" ? "Filmed from the side instead?" : "Filmed from the front instead?")
                .font(.system(size: 15)).foregroundStyle(Palette.mist)
            Button { switchShot() } label: {
                Text("Switch").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.fairway)
            }
        }.frame(maxWidth: .infinity)
    }

    private var faultColor: Color { analyzer.faults.isEmpty ? Palette.fairway : Palette.flag }

    private var verdictHero: some View {
        HStack(alignment: .center, spacing: 16) {
            if analyzer.faults.isEmpty {
                ZStack {
                    Circle().fill(Palette.fairway.opacity(0.16)).frame(width: 72, height: 72)
                    Image(systemName: "checkmark").font(.system(size: 34, weight: .heavy)).foregroundStyle(Palette.fairway)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Looking good!").font(.display(30)).foregroundStyle(Palette.chalk)
                    Text("Nothing major to fix.").font(.system(size: 17)).foregroundStyle(Palette.mist)
                }
            } else {
                Text("\(analyzer.faults.count)").font(.readout(72)).foregroundStyle(faultColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(analyzer.faults.count == 1 ? "thing to work on" : "things to work on")
                        .font(.display(26)).foregroundStyle(Palette.chalk)
                    Text("See below for what to do.").font(.system(size: 16)).foregroundStyle(Palette.mist)
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
    private var swingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SwingCanvas(image: currentThumb, frame: currentPlayFrame)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(alignment: .top, spacing: 8) {
                Text(adjusting ? "Slide to the right picture, then tap the moment to move it here."
                               : "Slide to watch, or tap a moment to see it.")
                    .font(.system(size: 16)).foregroundStyle(Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { withAnimation { adjusting.toggle() } } label: {
                    Text(adjusting ? "Done" : "Adjust")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.fairway)
                }
            }
            Filmstrip(thumbs: analyzer.frameThumbs, total: analyzer.frames.count,
                      playhead: $analyzer.playhead, events: analyzer.events)
            HStack(spacing: 8) { ForEach(SwingEvent.allCases) { keyMomentButton($0) } }
        }.card(10)
    }

    private func eventColor(_ e: SwingEvent) -> Color {
        switch e { case .address: return Palette.chalk; case .top: return Palette.fairway; case .impact: return Palette.amber }
    }
    private func eventLabel(_ e: SwingEvent) -> String {
        switch e { case .address: return "Address"; case .top: return "Top"; case .impact: return "Impact" }
    }

    // Tap to jump to a key moment; in Adjust mode, tap to move that moment to the
    // current frame (which re-grades the swing).
    private func keyMomentButton(_ e: SwingEvent) -> some View {
        let idx = analyzer.events[e]
        let here = idx != nil && analyzer.playhead == idx
        return Button {
            if adjusting { analyzer.assign(e, frame: analyzer.playhead) }
            else if let i = idx { withAnimation(.easeInOut(duration: 0.2)) { analyzer.playhead = i } }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(eventColor(e)).frame(width: 8, height: 8)
                Text(eventLabel(e)).font(.system(size: 15, weight: .semibold))
                if adjusting { Image(systemName: "pencil").font(.system(size: 11, weight: .bold)) }
            }
            .foregroundStyle(Palette.chalk)
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(here ? Palette.surface2 : Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke((here || adjusting) ? eventColor(e) : Palette.line, lineWidth: (here || adjusting) ? 2 : 1))
        }.buttonStyle(.plain).disabled(idx == nil && !adjusting)
    }

    private var diagnosis: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(analyzer.faults.isEmpty ? "Your swing" : "What to work on")
                .font(.display(22)).foregroundStyle(Palette.chalk)
            if analyzer.faults.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(Palette.fairway)
                    Text("No big problems. Your body stays steady and turns nicely.")
                        .font(.system(size: 17)).foregroundStyle(Palette.chalk)
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
            if let movie = try? await item.loadTransferable(type: Movie.self) { addVideo(movie.url) }
        }
    }

    /// The single entry point for any added video — auto-detect front vs side, then analyze.
    private func addVideo(_ url: URL) {
        videoURL = url
        shot = nil
        analyzer.reset(); plane.reset()
        detecting = true
        Task {
            let side = await OrientationDetector.looksLikeSide(url: url)
            await MainActor.run {
                detecting = false
                route(side ? .side : .front, url: url)
            }
        }
    }

    private func route(_ s: Shot, url: URL) {
        shot = s
        if s == .front { analyzer.analyze(url: url) } else { plane.analyze(url: url) }
    }

    /// Correction: re-read the same video as the other view.
    private func switchShot() {
        guard let u = videoURL, let s = shot else { return }
        let other: Shot = (s == .front) ? .side : .front
        if other == .front { plane.reset() } else { analyzer.reset() }
        route(other, url: u)
    }

    private func resetAll() {
        videoURL = nil; shot = nil; detecting = false; adjusting = false; pickerItem = nil
        analyzer.reset(); plane.reset()
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

// MARK: - Fault card — plain title + what to do, no jargon or numbers
struct FaultCard: View {
    let fault: Fault
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 2).fill(Palette.flag).frame(width: 5)
            VStack(alignment: .leading, spacing: 6) {
                Text(fault.name).font(.display(21)).foregroundStyle(Palette.chalk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(fault.note).font(.system(size: 17)).foregroundStyle(Palette.mist)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }
}

