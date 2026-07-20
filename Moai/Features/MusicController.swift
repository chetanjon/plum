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
        var duration: Double
        var volume: Double
        var shuffling: Bool
    }

    /// Playback position measured once per poll; views project it
    /// forward locally so the scrubber glides instead of stepping.
    struct PositionAnchor {
        var position: Double
        var date: Date
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

    /// Published only when something meaningful changes (track, play
    /// state, volume, shuffle); position lives in the anchor so the 1s
    /// poll doesn't rebuild the whole row every tick.
    @Published var nowPlaying: NowPlaying?
    @Published var artwork: NSImage?
    /// Artwork-derived accent for the whole island; neutral when idle.
    @Published private(set) var accent: Color = Theme.accentFallback

    private(set) var positionAnchor: PositionAnchor?

    private var timer: Timer?
    private let separator = "|||"
    /// Track identity the current artwork belongs to, so art is only
    /// fetched when the song changes.
    private var artworkKey: String?
    /// After an optimistic command, polls started before it are stale;
    /// skip publishing them for a beat instead of flickering back.
    private var suppressPollUntil = Date.distantPast

    /// One serial background lane for every AppleScript. Running them
    /// on the main thread stalled the UI for 50-200ms per call, once a
    /// second, which read as "glitchy" everywhere.
    private static let scriptQueue = DispatchQueue(label: "moai.music.script", qos: .userInitiated)

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Where playback is right now, projected from the last poll.
    func position(at date: Date = Date()) -> Double {
        guard let anchor = positionAnchor, let playing = nowPlaying else { return 0 }
        guard playing.isPlaying else { return anchor.position }
        let projected = anchor.position + date.timeIntervalSince(anchor.date)
        return playing.duration > 0 ? min(projected, playing.duration) : projected
    }

    // MARK: - Transport (optimistic: the UI flips now, the poll confirms)

    func play() { setPlayback(true) }
    func pause() { setPlayback(false) }

    func playPause() {
        setPlayback(!(nowPlaying?.isPlaying ?? false))
    }

    private func setPlayback(_ playing: Bool) {
        guard let app = activeApp() else { return }
        let current = position()
        nowPlaying?.isPlaying = playing
        positionAnchor = PositionAnchor(position: current, date: Date())
        holdPolls()
        run("tell application \"\(app.rawValue)\" to \(playing ? "play" : "pause")") { [weak self] _ in
            self?.refresh(force: true)
        }
    }

    func next() { skipTrack("next track") }
    func previous() { skipTrack("previous track") }

    private func skipTrack(_ verb: String) {
        guard let app = activeApp() else { return }
        positionAnchor = PositionAnchor(position: 0, date: Date())
        holdPolls()
        run("tell application \"\(app.rawValue)\" to \(verb)") { [weak self] _ in
            self?.refresh(force: true)
        }
    }

    func toggleShuffle() {
        guard let app = activeApp() else { return }
        nowPlaying?.shuffling.toggle()
        holdPolls()
        let script = app == .spotify
            ? "tell application \"Spotify\" to set shuffling to not shuffling"
            : "tell application \"Music\" to set shuffle enabled to not shuffle enabled"
        run(script) { [weak self] _ in
            self?.refresh(force: true)
        }
    }

    func seek(to seconds: Double) {
        guard let app = activeApp() else { return }
        positionAnchor = PositionAnchor(position: seconds, date: Date())
        holdPolls()
        run("tell application \"\(app.rawValue)\" to set player position to \(Int(seconds))") { [weak self] _ in
            self?.refresh(force: true)
        }
    }

    // MARK: - Volume (debounced: at most one script in flight per beat)

    private var pendingVolume: Double?
    private var volumeFlush: DispatchWorkItem?

    /// Live volume while the slider drags: sent at most every 120ms,
    /// always ending on the latest value.
    func previewVolume(_ volume: Double) {
        pendingVolume = volume
        guard volumeFlush == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.volumeFlush = nil
            if let target = self.pendingVolume {
                self.pendingVolume = nil
                self.sendVolume(target)
            }
        }
        volumeFlush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    /// The slider was released: land on this value exactly.
    func commitVolume(_ volume: Double) {
        volumeFlush?.cancel()
        volumeFlush = nil
        pendingVolume = nil
        sendVolume(volume)
    }

    private func sendVolume(_ volume: Double) {
        guard let app = activeApp() else { return }
        let clamped = max(0, min(100, Int(volume)))
        nowPlaying?.volume = Double(clamped)
        holdPolls()
        run("tell application \"\(app.rawValue)\" to set sound volume to \(clamped)")
    }

    func setVolume(_ volume: Double) {
        commitVolume(volume)
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

    /// Only talk to players that are already running. An AppleScript
    /// `tell` would otherwise launch the app, which nobody wants.
    private func activeApp() -> MusicApp? {
        let running = NSWorkspace.shared.runningApplications
            .compactMap { $0.bundleIdentifier }
        if running.contains(MusicApp.spotify.bundleID) { return .spotify }
        if running.contains(MusicApp.appleMusic.bundleID) { return .appleMusic }
        return nil
    }

    // MARK: - Poll

    /// One reset path for every "there is nothing playing" branch.
    private func clearNowPlaying() {
        if nowPlaying != nil { nowPlaying = nil }
        positionAnchor = nil
        artwork = nil
        artworkKey = nil
        updateAccent(from: nil)
    }

    private func holdPolls() {
        suppressPollUntil = Date().addingTimeInterval(0.8)
    }

    private func refresh(force: Bool = false) {
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
        let shuffleExpr = app == .spotify
            ? "shuffling"
            : "shuffle enabled"
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
            try
                set shuf to \(shuffleExpr)
            on error
                set shuf to false
            end try
            return s & "\(separator)" & t & "\(separator)" & a & "\(separator)" & al & "\(separator)" & pos & "\(separator)" & dur & "\(separator)" & vol & "\(separator)" & shuf & "\(separator)" & art
        end tell
        """
        run(source) { [weak self] output in
            self?.apply(output, from: app, force: force)
        }
    }

    private func apply(_ output: String?, from app: MusicApp, force: Bool) {
        // A poll that raced an optimistic command reports the world
        // from just before it; dropping one beat beats flickering.
        guard force || Date() >= suppressPollUntil else { return }
        guard let output else {
            clearNowPlaying()
            return
        }
        let parts = output.components(separatedBy: separator)
        guard parts.count >= 9, !parts[1].isEmpty else {
            clearNowPlaying()
            return
        }
        let fresh = NowPlaying(
            app: app,
            track: parts[1],
            artist: parts[2],
            album: parts[3],
            isPlaying: parts[0] == "playing",
            duration: Self.number(parts[5]),
            volume: Self.number(parts[6]),
            shuffling: parts[7] == "true"
        )
        positionAnchor = PositionAnchor(position: Self.number(parts[4]), date: Date())
        if fresh != nowPlaying {
            nowPlaying = fresh
            UserDefaults.standard.set(app.rawValue, forKey: lastAppKey)
        }
        refreshArtwork(app: app, key: parts[1] + "|" + parts[2], spotifyURL: parts[8])
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
            Self.scriptQueue.async { [weak self] in
                var error: NSDictionary?
                let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
                let data = (error == nil ? descriptor?.data : nil) ?? Data()
                let image = data.isEmpty ? nil : NSImage(data: data)
                Task { @MainActor in
                    guard let self, self.artworkKey == key else { return }
                    self.artwork = image
                    self.updateAccent(from: image)
                }
            }
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

    /// Run a script on the background lane; the completion hops back
    /// to the main actor with the string result (nil on any error).
    private func run(_ source: String, then completion: (@MainActor @Sendable (String?) -> Void)? = nil) {
        Self.scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let output = error == nil ? result?.stringValue : nil
            if let completion {
                Task { @MainActor in completion(output) }
            }
        }
    }
}
