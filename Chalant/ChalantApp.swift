import Sparkle
import SwiftUI

@main
struct ChalantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var statusItem: NSStatusItem?
    /// Sparkle, on a leash: its own scheduler is off (Info.plist
    /// SUEnableAutomaticChecks false; the island's quiet daily
    /// UpdateChecker remains the only detector). It acts when the
    /// user asks, and the app replaces itself and relaunches.
    private let updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    func applicationWillTerminate(_ notification: Notification) {
        // Stop the media bridge stream so no perl child outlives us.
        notchController?.viewModel.music.shutdown()
        notchController?.viewModel.activityServer.stop()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One-time inheritance from the Moai era: the rename changed
        // the bundle id, which changed the defaults domain, which
        // would have orphaned every setting, note, and focus streak.
        migrateFromMoai()
        // Press-and-hold accent picker is a remote-view sheet that
        // crashes when it tries to attach to the borderless notch
        // panel (ViewBridge SIGABRT, 2026-07-19). Held keys repeat
        // instead, the same trade VS Code makes.
        UserDefaults.standard.register(defaults: ["ApplePressAndHoldEnabled": false])

        // The island itself
        let controller = NotchWindowController()
        controller.show()
        notchController = controller
        controller.viewModel.installUpdate = { [weak self] in
            self?.updater.checkForUpdates(nil)
        }

        // Tiny menu bar item so the agent app can be quit
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // The house mark, drawn by hand: the little watcher. A floating
        // bar over a tapered body with one eye, its ember punched
        // through. Even-odd fill keeps the eye open. Matches the app
        // icon exactly; no capsule, so it can't read as a toggle.
        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let scale = 22.4, cx = 9.0, topY = 16.5  // y up: pill high, body below
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            let pw = 0.52 * scale, ph = 0.135 * scale
            path.appendRoundedRect(
                NSRect(x: cx - pw / 2, y: topY - ph, width: pw, height: ph),
                xRadius: ph / 2, yRadius: ph / 2
            )
            let bodyTop = topY - 0.20 * scale, bodyBot = topY - 0.66 * scale
            let tw = 0.60 * scale, bw = 0.46 * scale
            let r = 0.06 * scale
            let corners = [
                (cx - tw / 2, bodyTop), (cx + tw / 2, bodyTop),
                (cx + bw / 2, bodyBot), (cx - bw / 2, bodyBot),
            ]
            for i in 0..<4 {
                let cur = corners[i], prev = corners[(i + 3) % 4], next = corners[(i + 1) % 4]
                func unit(_ f: (Double, Double), _ t: (Double, Double)) -> (Double, Double) {
                    let dx = t.0 - f.0, dy = t.1 - f.1, L = max((dx * dx + dy * dy).squareRoot(), 0.0001)
                    return (dx / L, dy / L)
                }
                let up = unit(cur, prev), un = unit(cur, next)
                let p1 = NSPoint(x: cur.0 + up.0 * r, y: cur.1 + up.1 * r)
                let p2 = NSPoint(x: cur.0 + un.0 * r, y: cur.1 + un.1 * r)
                let ctl = NSPoint(x: cur.0, y: cur.1)
                if i == 0 { path.move(to: p1) } else { path.line(to: p1) }
                path.curve(to: p2, controlPoint1: ctl, controlPoint2: ctl)
            }
            path.close()
            let er = 0.085 * scale, ecy = topY - 0.42 * scale
            path.appendOval(in: NSRect(x: cx - er, y: ecy - er, width: er * 2, height: er * 2))
            NSColor.black.setFill()
            path.fill()
            return true
        }
        icon.isTemplate = true
        item.button?.image = icon
        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit Chalant",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        Task { @MainActor in
            guard let model = self.notchController?.viewModel else { return }
            model.expand()
            model.pane = .settings
        }
    }

    /// One-time inheritance from the app's earlier names. The newest
    /// era found wins (a Cove domain already carries what it took
    /// from Moai): its domain is copied wholesale, minus the keys
    /// that wore the old prefix, which are re-homed under chalant.
    /// Existing values are never overwritten; a fresh install finds
    /// nothing and moves on.
    private func migrateFromMoai() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "chalant.migrated") else { return }
        let eras = [("com.cj.plum", "plum."), ("com.cj.cove", "cove."), ("com.cj.moai", "moai.")]
        // Skip EVERY era's prefix, not just the current one: a Cove
        // domain still carried literal moai.* keys from its own
        // migration, and copying them wholesale littered the chalant
        // domain with dead keys (review-caught, harmless but untidy).
        let eraPrefixes = eras.map(\.1)
        for (domain, prefix) in eras {
            guard let old = defaults.persistentDomain(forName: domain) else { continue }
            for (key, value) in old
            where defaults.object(forKey: key) == nil
                && !eraPrefixes.contains(where: key.hasPrefix) {
                defaults.set(value, forKey: key)
            }
            for key in ["onboarded", "lastMusicApp", "lastUpdateNudge",
                        "notes", "focusStats", "focusGoal"] {
                if let value = old[prefix + key],
                   defaults.object(forKey: "chalant." + key) == nil {
                    defaults.set(value, forKey: "chalant." + key)
                }
            }
            break
        }
        defaults.set(true, forKey: "chalant.migrated")
    }
}
