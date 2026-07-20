import AppKit
import PDFKit

@MainActor
final class ShelfStore: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        var name: String { url.lastPathComponent }
    }

    @Published var items: [Item] = []
    private let maxItems = 12
    private let defaultsKey = "shelfBookmarks"

    init() {
        load()
    }

    func add(_ url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }
        items.insert(Item(url: url), at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        save()
    }

    /// A dragged web link becomes a .webloc in the app's folder, so it
    /// rides the same bookmark persistence as any stashed file.
    @discardableResult
    func addLink(_ link: URL) -> Bool {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: ["URL": link.absoluteString],
            format: .xml,
            options: 0
        ) else { return false }
        let name = "\(link.host ?? "link")-\(Self.uniqueSuffix()).webloc"
        let url = Self.droppedDirectory().appendingPathComponent(name)
        guard (try? data.write(to: url)) != nil else { return false }
        add(url)
        return true
    }

    private static func droppedDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Moai/Dropped", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func uniqueSuffix() -> String {
        String(UUID().uuidString.prefix(4))
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        save()
    }

    // MARK: Persistence

    /// Bookmarks, not paths: a stashed file keeps resolving after the
    /// user renames or moves it. Files deleted since last launch are
    /// quietly pruned.
    private func load() {
        guard let blobs = UserDefaults.standard.array(forKey: defaultsKey) as? [Data] else {
            return
        }
        items = blobs.compactMap { data in
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), FileManager.default.fileExists(atPath: url.path) else { return nil }
            return Item(url: url)
        }
        save()
    }

    private func save() {
        let blobs = items.compactMap { try? $0.url.bookmarkData() }
        UserDefaults.standard.set(blobs, forKey: defaultsKey)
    }

    func airDrop(_ item: Item) {
        NSSharingService(named: .sendViaAirDrop)?
            .perform(withItems: [item.url])
    }

    /// Best-effort text extraction so Moai can answer questions
    /// about a stashed file. PDFs and any UTF-8 text for v1.
    func extractText(_ item: Item, limit: Int = 8000) -> String? {
        let url = item.url
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url),
                  let text = document.string else { return nil }
            return String(text.prefix(limit))
        }
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            return String(text.prefix(limit))
        }
        return nil
    }
}
