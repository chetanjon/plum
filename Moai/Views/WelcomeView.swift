import SwiftUI

/// The first hello: three quiet steps inside the island itself. No
/// separate window, no permission wall; macOS asks for things as they
/// are first used, and the tour just says so.
struct WelcomeView: View {
    @ObservedObject var model: NotchViewModel
    @Environment(\.moaiAccent) private var accent

    private let steps = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            controls
        }
        .frame(height: 250)
        .onExitCommand { model.finishWelcome() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.welcomeStep {
        case 0:
            step(
                title: "I live up here.",
                lines: [
                    ("cursorarrow.motionlines", "Glide to the top of the screen and I open."),
                    ("mic.fill", "Hold the notch, tap the mic, or hit Option-Space anywhere, and talk."),
                    ("lock.fill", "Everything runs on this Mac. Your words never leave it."),
                ]
            )
        case 1:
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Say it.")
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.textPrimary)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    verb("remind me to call amma at 6")
                    verb("focus 25")
                    verb("left half")
                    verb("open figma")
                    verb("cancel my 3pm")
                    verb("find parcel")
                }
                Text("macOS will ask for the mic and speech the first time. That is the deal working; both stay on this Mac.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textHint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        default:
            step(
                title: "The rest finds you.",
                lines: [
                    ("tray.and.arrow.down.fill", "Drag any file or screenshot upward; a bubble meets it halfway."),
                    ("doc.on.doc", "Copies land in Clips, files on the Shelf, thoughts in Notes."),
                    ("calendar", "Your day stays private until you switch Calendar on in Settings."),
                ]
            )
        }
    }

    private func step(
        title: String,
        lines: [(String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(title)
                .font(Theme.Fonts.title)
                .foregroundStyle(Theme.textPrimary)
            ForEach(lines, id: \.1) { symbol, text in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                    Image(systemName: symbol)
                        .font(Theme.Fonts.icon(.s))
                        .foregroundStyle(accent)
                        .frame(width: 18)
                    Text(text)
                        .font(Theme.Fonts.reading)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func verb(_ text: String) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text("\u{201C}\(text)\u{201D}")
                .font(Theme.Fonts.bodyMono)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var controls: some View {
        HStack(spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.snug) {
                ForEach(0..<steps, id: \.self) { index in
                    Circle()
                        .fill(
                            index == model.welcomeStep
                                ? AnyShapeStyle(accent)
                                : AnyShapeStyle(Color.white.opacity(0.15))
                        )
                        .frame(width: 5, height: 5)
                }
            }
            Spacer()
            if model.welcomeStep < steps - 1 {
                Button("Skip") { model.finishWelcome() }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Button {
                if model.welcomeStep < steps - 1 {
                    withAnimation(Theme.Motion.content) { model.welcomeStep += 1 }
                } else {
                    model.finishWelcome()
                }
            } label: {
                Text(model.welcomeStep < steps - 1 ? "Next" : "Begin")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, Theme.Space.l)
                    .frame(minHeight: 26)
                    .background(Capsule().fill(Theme.textPrimary))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
        }
    }
}
