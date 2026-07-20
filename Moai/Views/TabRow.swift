import SwiftUI

/// The lower-panel switcher: Today (when your day is turned on) plus
/// whichever tools you keep, and the settings gear. Items are icon-only
/// until selected — the active one wears its label, so the row stays
/// quiet.
struct Switcher: View {
    @ObservedObject var model: NotchViewModel
    let todayEnabled: Bool
    let tools: [NotchViewModel.Tab]

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if todayEnabled {
                item(.today)
            }
            ForEach(tools, id: \.self) { item($0) }
            Spacer(minLength: 0)
            HoverGlyphButton(symbol: "gearshape", scale: .s, tint: Theme.textTertiary) {
                withAnimation(Theme.Motion.content) { model.pane = .settings }
            }
        }
    }

    private func item(_ tab: NotchViewModel.Tab) -> some View {
        let on = model.tab == tab
        return Button {
            withAnimation(Theme.Motion.content) { model.tab = tab }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: Self.symbol(tab))
                    .font(Theme.Fonts.icon(.s))
                if on {
                    Text(Self.label(tab)).font(Theme.Fonts.label)
                }
            }
            .foregroundStyle(on ? Theme.textPrimary : Theme.textTertiary)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(on ? 0.08 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(Self.label(tab))
    }

    static func symbol(_ tab: NotchViewModel.Tab) -> String {
        switch tab {
        case .today: return "calendar"
        case .ask: return "sparkles"
        case .links: return "square.grid.2x2"
        case .clipboard: return "doc.on.clipboard"
        case .shelf: return "tray"
        case .focus: return "timer"
        }
    }

    static func label(_ tab: NotchViewModel.Tab) -> String {
        switch tab {
        case .today: return "Today"
        case .ask: return "Answer"
        case .links: return "Go"
        case .clipboard: return "Clips"
        case .shelf: return "Shelf"
        case .focus: return "Focus"
        }
    }
}
