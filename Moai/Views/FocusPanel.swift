import SwiftUI

/// The pomodoro home: presets when idle, and while a session runs, a
/// progress ring, the countdown, round dots, noise, and transport.
struct FocusPanel: View {
    @ObservedObject var focus: FocusController
    @Environment(\.moaiAccent) private var accent

    var body: some View {
        if focus.isActive {
            activeCard
        } else {
            presets
        }
    }

    // MARK: Idle — pick a session length

    private var presets: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FOCUS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 8) {
                presetChip(15)
                presetChip(25)
                presetChip(50)
            }
            Text("Four rounds to a set, short breaks between, a long one after. Noise optional.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func presetChip(_ minutes: Int) -> some View {
        Button {
            focus.start(work: minutes)
        } label: {
            VStack(spacing: 2) {
                Text("\(minutes)")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Text("min")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 64)
            .padding(.vertical, 10)
            .moaiCard(radius: Theme.Radius.card)
        }
        .buttonStyle(.plain)
    }

    // MARK: Active session

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ring
                VStack(alignment: .leading, spacing: 3) {
                    Text(focus.phase == .work ? "FOCUS" : "BREAK")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(focus.phase == .work ? accent : Theme.textTertiary)
                    Text(focus.display)
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .opacity(focus.isPaused ? 0.45 : 1)
                    roundDots
                }
                Spacer()
                controls
            }
            HStack(spacing: 10) {
                Text("noise")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                noiseButton("B", .brown)
                noiseButton("W", .white)
                noiseButton("P", .pink)
                Spacer()
                if focus.isPaused {
                    Text("paused")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .animation(Theme.Motion.content, value: focus.isPaused)
        .animation(Theme.Motion.content, value: focus.phase)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.003, focus.progress))
                .stroke(
                    focus.phase == .work ? accent : Theme.accentFallback,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: focus.progress)
            Text("\(focus.roundInSet)")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(width: 54, height: 54)
    }

    private var roundDots: some View {
        HStack(spacing: 5) {
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
        HStack(spacing: 14) {
            Button {
                focus.togglePause()
            } label: {
                Image(systemName: focus.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)
            Button {
                focus.skip()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            Button {
                focus.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private func noiseButton(_ label: String, _ color: NoiseEngine.NoiseColor) -> some View {
        Button {
            focus.setNoise(color)
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(focus.noiseColor == color ? accent : Theme.textTertiary)
        }
        .buttonStyle(.plain)
    }
}
