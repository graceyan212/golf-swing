import SwiftUI
import UIKit

/// One saved swing check — a lightweight summary + a thumbnail, so the user can
/// look back and see progress. (Videos aren't stored, just the result + a frame.)
struct SwingRecord: Identifiable, Codable {
    let id: String
    let date: Date
    let kind: String       // "front" or "side"
    let headline: String   // e.g. "2 things to work on" / "Good swing path"
    let detail: String
    let thumb: String      // thumbnail filename (may be empty)
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var records: [SwingRecord] = []
    private let dir: URL
    private var indexURL: URL { dir.appendingPathComponent("index.json") }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("history", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: indexURL),
              let recs = try? dec.decode([SwingRecord].self, from: data) else { return }
        records = recs.sorted { $0.date > $1.date }
    }

    private func persist() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(records) { try? data.write(to: indexURL) }
    }

    func add(kind: String, headline: String, detail: String, thumb: UIImage?) {
        let id = UUID().uuidString
        var file = ""
        if let t = thumb, let jpg = t.jpegData(compressionQuality: 0.7) {
            file = "\(id).jpg"
            try? jpg.write(to: dir.appendingPathComponent(file))
        }
        records.insert(SwingRecord(id: id, date: Date(), kind: kind,
                                   headline: headline, detail: detail, thumb: file), at: 0)
        persist()
    }

    func image(_ r: SwingRecord) -> UIImage? {
        guard !r.thumb.isEmpty else { return nil }
        return UIImage(contentsOfFile: dir.appendingPathComponent(r.thumb).path)
    }

    func delete(_ r: SwingRecord) {
        if !r.thumb.isEmpty { try? FileManager.default.removeItem(at: dir.appendingPathComponent(r.thumb)) }
        records.removeAll { $0.id == r.id }
        persist()
    }
}

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    var onClose: () -> Void
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    var body: some View {
        ZStack {
            Palette.turf.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Your swings").font(.display(30)).foregroundStyle(Palette.chalk)
                        Spacer()
                        Button { onClose() } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 27)).foregroundStyle(Palette.mist)
                        }
                    }
                    if store.records.isEmpty {
                        Text("No swings yet. Check a swing and it'll show up here, so you can look back and see how you're doing.")
                            .font(.system(size: 17)).foregroundStyle(Palette.mist).lineSpacing(2)
                            .padding(.top, 8)
                    } else {
                        ForEach(store.records) { card($0) }
                    }
                }.padding(20)
            }
        }
    }

    private func card(_ r: SwingRecord) -> some View {
        HStack(spacing: 14) {
            Group {
                if let img = store.image(r) { Image(uiImage: img).resizable().scaledToFill() }
                else { Palette.surface2 }
            }
            .frame(width: 62, height: 82).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(r.kind == "side" ? "SIDE VIEW" : "FRONT VIEW")
                    .font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(Palette.mist)
                Text(r.headline).font(.display(19)).foregroundStyle(Palette.chalk)
                Text(r.detail).font(.system(size: 14)).foregroundStyle(Palette.mist).lineLimit(2)
                Text(Self.fmt.string(from: r.date)).font(.system(size: 12)).foregroundStyle(Palette.mist)
            }
            Spacer(minLength: 0)
            Button { withAnimation { store.delete(r) } } label: {
                Image(systemName: "trash").font(.system(size: 15)).foregroundStyle(Palette.mist)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }
}
