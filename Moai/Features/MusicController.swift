import AppKit
import Combine
import SwiftUI

@MainActor
final class MusicController: ObservableObject {
    struct NowPlaying: Equatable {
        var app: MusicApp
        var track: String
        var artist: String
        var album: String
        var isPlaying: Bool
        var position: Double
        var duration: Double
        var volume: Double
    }

    enum MusicApp: String {
        case spotify = "Spotify"
        case appleMusic = "Music"

        var bundleID: String {
            switch self {
            case .spotify: return "com.spotify.client"
            case .appleMusic: return "com.apple.Music"
            }
        }
    }

    @Published var nowPlaying: NowPlaying?
    @Published var artwork: NSImage?
    /// Artwork-derived accent for the whole island; neutral when idle.
    @Published private(set) var accent: Color = Theme.accentFallback

    private var timer: Timer?
    private let separator = "|||"
    /// Track identity the current artwork belongs to, so art is only
    /// fetched when the song changes.
    private var artworkKey: String?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func play() { command("play") }
    func pause() { command("pause") }
    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    func seek(to seconds: Double) {
        guard let app = activeApp() else { return }
        runScript("tell application \"\(app.rawValue)\" to set player position to \(Int(seconds))")
        refresh()
    }

    func setVolume(_ volume: Double) {
        guard let app = activeApp() else { return }
        let clamped = max(0, min(100, Int(volume)))
        runScript("tell application \"\(app.rawValue)\" to set sound volume to \(clamped)")
    }

    /// Only talk to players that are already running. An AppleScript
    /// `tell` would otherwise launch the app, which nobody wants.
    private func activeApp() -> MusicApp? {
        let running = NSWorkspace.shared.runningApplications
            .compactMap { $0.bundleIdentifier }
        if running.contains(MusicApp.spotify.bundleID) { return .spotify }
        if running.contains(MusicApp.appleMusic.bundleID) { return .appleMusic }
        return nil
    }

    // MARK: - Quick access

    private let lastAppKey = "moai.lastMusicApp"

    /// The app the quick-access chip would open right now: whatever is
    /// running, else whatever played last, else whatever is installed.
    var preferredApp: MusicApp? {
        if let app = activeApp() { return app }
        if let raw = UserDefaults.standard.string(forKey: lastAppKey),
           let app = MusicApp(rawValue: raw), isInstalled(app) {
            return app
        }
        if isInstalled(.spotify) { return .spotify }
        if isInstalled(.appleMusic) { return .appleMusic }
        return nil
    }

    /// Open the preferred player; with neither installed, fall back to
    /// YouTube Music in the browser so the chip always does something.
    func openMusicApp() {
        if let app = preferredApp,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else if let url = URL(string: "https://music.youtube.com") {
            NSWorkspace.shared.open(url)
        }
    }

    private func isInstalled(_ app: MusicApp) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) != nil
    }

    private func command(_ verb: String) {
        guard let app = activeApp() else { return }
        runScript("tell application \"\(app.rawValue)\" to \(verb)")
        refresh()
    }

    /// One reset path for every "there is nothing playing" branch.
    private func clearNowPlaying() {
        nowPlaying = nil
        artwork = nil
        artworkKey = nil
        updateAccent(from: nil)
    }

    private func refresh() {
        guard let app = activeApp() else {
            clearNowPlaying()
            return
        }
        // Spotify reports duration in milliseconds, Music in seconds.
        let durationExpr = app == .spotify
            ? "(duration of current track) / 1000"
            : "duration of current track"
        let artExpr = app == .spotify
            ? "artwork url of current track"
            : "\"\""
        let source = """
        tell application "\(app.rawValue)"
            if player state is playing then
                set s to "playing"
            else
                set s to "paused"
            end if
            try
                set t to name of current track
                set a to artist of current track
                set al to album of current track
                set dur to \(durationExpr)
                set art to \(artExpr)
            on error
                set t to ""
                set a to ""
                set al to ""
                set dur to 0
                set art to ""
            end try
            set pos to player position
            set vol to sound volume
            return s & "\(separator)" & t & "\(separator)" & a & "\(separator)" & al & "\(separator)" & pos & "\(separator)" & dur & "\(separator)" & vol & "\(separator)" & art
        end tell
        """
        guard let output = runScript(source) else {
            clearNowPlaying()
            return
        }
        let parts = output.components(separatedBy: separator)
        guard parts.count >= 8, !parts[1].isEmpty else {
            clearNowPlaying()
            return
        }
        nowPlaying = NowPlaying(
            app: app,
            track: parts[1],
            artist: parts[2],
            album: parts[3],
            isPlaying: parts[0] == "playing",
            position: Self.number(parts[4]),
            duration: Self.number(parts[5]),
            volume: Self.number(parts[6])
        )
        UserDefaults.standard.set(app.rawValue, forKey: lastAppKey)
        refreshArtwork(app: app, key: parts[1] + "|" + parts[2], spotifyURL: parts[7])
    }

    // MARK: - Artwork

    private func refreshArtwork(app: MusicApp, key: String, spotifyURL: String) {
        guard key != artworkKey else { return }
        artworkKey = key
        switch app {
        case .spotify:
            guard let url = URL(string: spotifyURL) else {
                artwork = nil
                updateAccent(from: nil)
                return
            }
            // (Track info stays; only the art is unavailable.)
            Task { [weak self] in
                let image = (try? await URLSession.shared.data(from: url))
                    .flatMap { NSImage(data: $0.0) }
                await MainActor.run {
                    guard let self, self.artworkKey == key else { return }
                    self.artwork = image
                    self.updateAccent(from: image)
                }
            }
        case .appleMusic:
            let source = """
            tell application "Music"
                try
                    return data of artwork 1 of current track
                on error
                    return ""
                end try
            end tell
            """
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else {
                artwork = nil
                updateAccent(from: nil)
                return
            }
            let descriptor = script.executeAndReturnError(&error)
            let data = descriptor.data
            artwork = (error == nil && !data.isEmpty) ? NSImage(data: data) : nil
            updateAccent(from: artwork)
        }
    }

    /// Extraction runs on a 24×24 downsample, once per track change,
    /// cheap enough to do inline where the artwork lands.
    private func updateAccent(from image: NSImage?) {
        let newValue = image.flatMap(AccentExtractor.accent(from:)) ?? Theme.accentFallback
        withAnimation(Theme.Motion.accent) {
            accent = newValue
        }
    }

    /// AppleScript renders reals with the locale's decimal separator.
    private static func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    @discardableResult
    private func runScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result.stringValue
    }
}
