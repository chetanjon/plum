import SwiftUI

/// The countdown home: pomodoro presets and a plain timer when idle;
/// while either runs, a progress ring, the countdown, and controls.
struct FocusPanel: View {
    @ObservedObject var focus: FocusController
    @ObservedObject var timer: CountdownController
    @ObservedObject var stats: FocusStatsStore
    @Environment(\.moaiAccent) private var accent

    var body: some View {
        if focus.isActive {
            activeCard
        } else if timer.isActive {
            timerCard
        } else {
            presets
        }
    }

    // MARK: Idle, pick a session length

    private var presets: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SectionHeader(title: "Focus")
            HStack(spacing: Theme.Space.m) {
                presetChip(15, "short")
                presetChip(25, "classic")
                presetChip(50, "deep")
            }
            Text("Four rounds to a set, short breaks between, a long one after. Noise optional.")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textHint)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Space.m) {
                Text("Just a timer")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                ForEach([5, 10, 20], id: \.self) { minutes in
                    timerChip(minutes)
                }
            }
            .padding(.top, Theme.Space.xs)
            if !stats.days.isEmpty {
                statsBlock
                    .padding(.top, Theme.Space.s)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Quiet analytics: a week of bars, the numbers that matter

    private var statsBlock: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.xl) {
            HStack(alignment: .bottom, spacing: Theme.Space.s) {
                ForEach(stats.lastWeek) { slice in
                    VStack(spacing: 3) {
                        Capsule()
                            .fill(
                                slice.isToday
                                    ? AnyShapeStyle(accent)
                                    : AnyShapeStyle(Color.white.opacity(0.14))
                            )
                            .frame(width: 4, height: barHeight(slice))
                        Text(Self.dayLetter(slice.day))
                            .font(Theme.Fonts.micro)
                            .foregroundStyle(slice.isToday ? Theme.textTertiary : Theme.textGhost)
                    }
                    .help("\(Self.dayName(slice.day)), \(FocusStatsStore.clock(slice.minutes))")
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                if stats.todayMinutes > 0 {
                    Text("\(FocusStatsStore.clock(stats.todayMinutes)) today")
                        .font(Theme.Fonts.captionMono)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("\(FocusStatsStore.clock(stats.weekMinutes)) this week")
                    .font(Theme.Fonts.microMono)
                    .foregroundStyle(Theme.textTertiary)
                if stats.streak >= 2 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(Theme.Fonts.icon(.xs))
                            .foregroundStyle(accent)
                        Text("\(stats.streak) days")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    /// Bars scale to the week's best day; a worked day never drops
    /// below a visible stub, an empty day stays a quiet dot.
    private func barHeight(_ slice: FocusStatsStore.DaySlice) -> CGFloat {
        let top = stats.lastWeek.map(\.minutes).max() ?? 0
        guard top > 0, slice.minutes > 0 else { return 3 }
        return 5 + 19 * CGFloat(slice.minutes) / CGFloat(top)
    }

    private static let letterFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    private static let nameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static func dayLetter(_ day: Date) -> String {
        letterFormatter.string(from: day)
    }

    private static func dayName(_ day: Date) -> String {
        nameFormatter.string(from: day)
    }

    private func timerChip(_ minutes: Int) -> some View {
        Button {
            timer.start(minutes: minutes)
        } label: {
            Text("\(minutes) min")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Space.m)
                .frame(minHeight: 22)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().strokeBorder(Theme.hairlineFaint, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Plain timer running

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(spacing: Theme.Space.xl) {
                ProgressRing(
                    progress: timer.progress,
                    size: 54,
                    lineWidth: 3,
                    tint: accent,
                    trackOpacity: 0.08
                ) {
                    Image(systemName: "timer")
                        .font(Theme.Fonts.icon(.m))
                        .foregroundStyle(Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    SectionHeader(title: "Timer", tint: accent)
                    Text(timer.display)
                        .font(Theme.Fonts.display)
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                CloseButton(scale: .s) {
                    timer.stop()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Space.xs)
    }

    private func presetChip(_ minutes: Int, _ mood: String) -> some View {
        Button {
            focus.start(work: minutes)
        } label: {
            VStack(spacing: 2) {
                Text("\(minutes)")
                    .font(Theme.Fonts.numeral)
                    .foregroundStyle(Theme.textPrimary)
                Text(mood)
                    .font(Theme.Fonts.micro)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 64)
            .padding(.vertical, Theme.Space.l)
            .moaiCard(radius: Theme.Radius.card)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .hoverHighlight(radius: Theme.Radius.card)
    }

    // MARK: Active session

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(spacing: Theme.Space.xl) {
                breathingRing
                VStack(alignment: .leading, spacing: 3) {
                    SectionHeader(
                        title: focus.phase == .work ? "Focus" : "Break",
                        tint: focus.phase == .work ? accent : Theme.textTertiary
                    )
                    Text(focus.display)
                        .font(Theme.Fonts.display)
                        .foregroundStyle(Theme.textPrimary)
                        .opacity(focus.isPaused ? 0.45 : 1)
                    roundDots
                }
                Spacer()
                controls
            }
            if focus.isPaused {
                Text("paused")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Space.xs)
        .animation(Theme.Motion.content, value: focus.isPaused)
        .animation(Theme.Motion.content, value: focus.phase)
    }

    private var sessionRing: some View {
        ProgressRing(
            progress: focus.progress,
            size: 54,
            lineWidth: 3,
            tint: focus.phase == .work ? accent : Theme.accentFallback,
            trackOpacity: 0.08
        ) {
            Text("\(focus.roundInSet)")
                .font(Theme.Fonts.counterMono)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// During work the ring carries a faint breathing halo, the
    /// session is alive. Breaks and pauses sit still.
    @ViewBuilder
    private var breathingRing: some View {
        if Theme.Feel.current.ambient, focus.phase == .work, !focus.isPaused {
            TimelineView(.animation(minimumInterval: 1 / 15)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let breath = 0.5 + 0.5 * sin(t / (1.6 * Theme.Motion.ambientSlow))
                sessionRing
                    .shadow(color: accent.opacity(0.10 + 0.15 * breath), radius: 8)
            }
        } else {
            sessionRing
        }
    }

    private var roundDots: some View {
        HStack(spacing: Theme.Space.snug) {
            ForEach(1...4, id: \.self) { round in
                Circle()
                    .fill(
                        round < focus.roundInSet ? AnyShapeStyle(accent)
                            : round == focus.roundInSet ? AnyShapeStyle(accent.opacity(0.55))
                            : AnyShapeStyle(Color.white.opacity(0.12))
                    )
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: Theme.Space.s) {
            HoverGlyphButton(
                symbol: focus.isPaused ? "play.fill" : "pause.fill",
                scale: .m,
                tint: Theme.textPrimary
            ) {
                focus.togglePause()
            }
            HoverGlyphButton(
                symbol: "forward.end.fill",
                scale: .s,
                tint: Theme.textSecondary
            ) {
                focus.skip()
            }
            CloseButton(scale: .s) {
                focus.stop()
            }
        }
    }
}
