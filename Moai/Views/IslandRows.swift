import SwiftUI

/// The music row, compact: artwork, title/artist, a slim scrubber, and
/// transport. Volume and timestamps are gone — they made the row wide
/// for little gain; the system keys handle volume, the bar shows time.
struct MusicRow: View {
    @ObservedObject var music: MusicController
    @Environment(\.moaiAccent) private var accent
    @State private var scrubPosition: Double?

    var body: some View {
        if let playing = music.nowPlaying {
            HStack(spacing: Theme.Space.l) {
                artworkView

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Theme.Space.s) {
                        Text(playing.track)
                            .font(Theme.Fonts.bodyEmphasis)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(playing.artist)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Slider(
                        value: Binding(
                            get: { scrubPosition ?? playing.position },
                            set: { scrubPosition = $0 }
                        ),
                        in: 0...max(playing.duration, 1),
                        onEditingChanged: { editing in
                            if !editing, let target = scrubPosition {
                                music.seek(to: target)
                                scrubPosition = nil
                            }
                        }
                    )
                    .controlSize(.mini)
                    .tint(accent)
                }

                HStack(spacing: Theme.Space.s) {
                    HoverGlyphButton(symbol: "backward.fill", scale: .s, tint: Theme.textPrimary) {
                        music.previous()
                    }
                    Button {
                        playing.isPlaying ? music.pause() : music.play()
                    } label: {
                        Image(systemName: playing.isPlaying ? "pause.fill" : "play.fill")
                            .font(Theme.Fonts.icon(.m, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.94)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    HoverGlyphButton(symbol: "forward.fill", scale: .s, tint: Theme.textPrimary) {
                        music.next()
                    }
                }
            }
        }
    }

    private var artworkView: some View {
        Group {
            if let artwork = music.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Theme.surface
                    Image(systemName: "music.note")
                        .font(Theme.Fonts.icon(.l))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

/// The ambience row: six icons, no words. The active one tints; its
/// volume appears only once something is playing.
struct AmbienceRow: View {
    @ObservedObject var ambience: AmbienceController

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(NoiseEngine.NoiseColor.allCases, id: \.self) { color in
                NoiseButton(
                    color: color,
                    selected: ambience.active == color,
                    compact: true
                ) {
                    ambience.toggle(color)
                }
            }
            Spacer(minLength: 0)
            if ambience.active != nil {
                Slider(value: $ambience.volume, in: 0...1)
                    .controlSize(.mini)
                    .tint(Color.white.opacity(0.5))
                    .frame(width: 44)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.content, value: ambience.active)
    }
}

/// The answer surface: the reply, the working state, or — when idle —
/// a voice-forward hint. Input is voice (the mic, or holding the notch),
/// not a text field.
struct AnswerView: View {
    @ObservedObject var model: NotchViewModel
    @Environment(\.moaiAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let context = model.pendingContext {
                contextChip(context.name)
            }
            if model.isWorking, model.answer.isEmpty {
                ThinkingDots()
                    .padding(.top, Theme.Space.xs)
            } else if !model.errorText.isEmpty {
                Text(model.errorText)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.answer.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Hold the notch or tap the mic — I'm listening.")
                        .font(Theme.Fonts.reading)
                        .foregroundStyle(Theme.textHint)
                    Text("remind me to call amma at 6 · what's on today · focus 25 · note: an idea")
                        .font(Theme.Fonts.label)
                        .fontWeight(.regular)
                        .foregroundStyle(Theme.textGhost)
                }
            } else if model.answer.count > 900 {
                ScrollView {
                    answerText
                }
                .frame(maxHeight: 280)
            } else {
                answerText
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var answerText: some View {
        Text(model.answer)
            .font(Theme.Fonts.reading)
            .lineSpacing(3)
            .foregroundStyle(Theme.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func contextChip(_ name: String) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "paperclip")
                .font(Theme.Fonts.icon(.xs))
            Text(name)
                .font(Theme.Fonts.caption)
                .lineLimit(1)
            Button {
                model.pendingContext = nil
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.Fonts.icon(.xs, weight: .bold))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
        .foregroundStyle(accent)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.xs)
        .background(Capsule().fill(accent.opacity(0.12)))
        .overlay(Capsule().strokeBorder(accent.opacity(0.4), lineWidth: 1))
    }
}
