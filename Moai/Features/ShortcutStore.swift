import AppKit

/// User-defined quick links: websites, apps, folders — anything
/// NSWorkspace can open. Persisted as JSON in UserDefaults.
@MainActor
final class ShortcutStore: ObservableObject {
    struct Shortcut: Identifiable, Codable, Equatable {
        var id = UUID()
        var title: String
        var link: String
    }

    @Published private(set) var shortcuts: [Shortcut] = [] {
        didSet { save() }
    }

    private let defaultsKey = "shortcuts"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([Shortcut].self, from: data) {
            shortcuts = saved
        }
    }

    func add(title: String, link: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLink.isEmpty else { return }
        let name = cleanTitle.isEmpty ? Self.suggestedTitle(for: cleanLink) : cleanTitle
        shortcuts.append(Shortcut(title: name, link: cleanLink))
    }

    func remove(_ shortcut: Shortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
    }

    @discardableResult
    func open(_ shortcut: Shortcut) -> Bool {
        guard let url = Self.resolvedURL(for: shortcut.link) else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// First shortcut whose title matches the spoken/typed name.
    func match(_ name: String) -> Shortcut? {
        let query = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }
        return shortcuts.first { $0.title.lowercased() == query }
            ?? shortcuts.first { $0.title.lowercased().contains(query) }
    }

    /// "github.com" → https URL; "/Applications/X.app" or "~/Docs" →
    /// file URL; full schemes pass through.
    static func resolvedURL(for raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("/") || text.hasPrefix("~") {
            return URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
        }
        if let url = URL(string: text), url.scheme != nil {
            return url
        }
        guard text.contains(".") || text.contains(":") else { return nil }
        return URL(string: "https://" + text)
    }

    /// A real app/file icon for local links; nil for the web (the view
    /// draws a monogram instead).
    static func fileIcon(for link: String) -> NSImage? {
        guard let url = resolvedURL(for: link), url.isFileURL,
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func suggestedTitle(for link: String) -> String {
        guard let url = resolvedURL(for: link) else { return link }
        if url.isFileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        let host = url.host ?? link
        let stripped = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return stripped.split(separator: ".").first.map(String.init)?.capitalized ?? stripped
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
