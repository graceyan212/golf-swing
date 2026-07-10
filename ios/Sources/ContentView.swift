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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Record a face-on swing → get your key positions and what's wrong. Runs entirely on-device.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    banner
                    controls
                    if analyzer.busy { ProgressView(value: analyzer.progress) }
                    Text(analyzer.status).font(.footnote).foregroundStyle(.secondary)
                    if !analyzer.frames.isEmpty && !analyzer.events.isEmpty { results }
                }
                .padding()
            }
            .navigationTitle("Swing Check")
        }
        .onChange(of: pickerItem) { _, item in loadPicked(item) }
        .fullScreenCover(isPresented: $showCamera) {
            CameraRecorder { url in analyzer.analyze(url: url) }.ignoresSafeArea()
        }
        .onAppear {
            if CommandLine.arguments.contains("-autodemo") { runDemo() }
        }
    }

    private var banner: some View {
        Text("Prototype — film face-on, full body in frame, steady camera, trimmed to the swing. Positions are auto-detected and approximate; drag a slider to fix any.")
            .font(.caption).foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $pickerItem, matching: .videos) {
                Label("Choose a swing video", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button { showCamera = true } label: {
                Label("Record a swing", systemImage: "video").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            if Bundle.main.url(forResource: "demo_swing", withExtension: "mp4") != nil {
                Button { runDemo() } label: {
                    Label("Try the demo clip", systemImage: "play.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            eventCanvas
            Text(caption).font(.caption).foregroundStyle(.secondary)
            Picker("Position", selection: $analyzer.selected) {
                ForEach(SwingEvent.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            ForEach(SwingEvent.allCases) { e in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(e.rawValue): frame \((analyzer.events[e] ?? 0) + 1) / \(analyzer.frames.count)")
                        .font(.caption2).foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(analyzer.events[e] ?? 0) },
                            set: { analyzer.selected = e; analyzer.setEvent(e, index: Int($0.rounded())) }),
                        in: 0...Double(max(1, analyzer.frames.count - 1)), step: 1)
                }
            }
            faultsView
        }
    }

    private var caption: String {
        let e = analyzer.selected
        let f = (analyzer.events[e]).flatMap { $0 < analyzer.frames.count ? analyzer.frames[$0] : nil }
        if let f, !f.ok { return "\(e.rawValue): no body detected here — drag the slider to a frame where you're in view." }
        return "\(e.rawValue)"
    }

    private var eventCanvas: some View {
        let e = analyzer.selected
        let img = analyzer.eventImages[e]
        let f = (analyzer.events[e]).flatMap { $0 < analyzer.frames.count ? analyzer.frames[$0] : nil }
        let aspect = img?.size ?? CGSize(width: 3, height: 4)
        return Canvas { context, size in
            if let img {
                let resolved = context.resolve(Image(uiImage: img))
                context.draw(resolved, in: CGRect(origin: .zero, size: size))
            }
            guard let f, f.ok else { return }
            for (a, b) in Self.bones {
                if let pa = f.draw[a], let pb = f.draw[b] {
                    var path = Path()
                    path.move(to: CGPoint(x: pa.x * size.width, y: pa.y * size.height))
                    path.addLine(to: CGPoint(x: pb.x * size.width, y: pb.y * size.height))
                    context.stroke(path, with: .color(.green), lineWidth: 3)
                }
            }
            for (_, p) in f.draw {
                let r = CGRect(x: p.x * size.width - 4, y: p.y * size.height - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: r), with: .color(.green))
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var faultsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if analyzer.faults.isEmpty {
                Text("✓ No major faults flagged — sway, hip slide, and early extension are within range.")
                    .font(.subheadline)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            } else {
                ForEach(analyzer.faults) { fault in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fault.name.capitalized).font(.headline).foregroundStyle(.red)
                        Text(fault.note).font(.footnote)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
            }
        }
    }

    private func loadPicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let movie = try? await item.loadTransferable(type: Movie.self) {
                analyzer.analyze(url: movie.url)
            } else {
                analyzer.status = "Couldn't load that video."
            }
        }
    }

    private func runDemo() {
        if let u = Bundle.main.url(forResource: "demo_swing", withExtension: "mp4") {
            analyzer.analyze(url: u)
        }
    }
}
