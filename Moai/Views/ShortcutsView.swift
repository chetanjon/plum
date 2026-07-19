import SwiftUI

/// The Go tab: a quiet grid of user-defined shortcuts — websites,
/// apps, folders. Click to launch and the island slips shut.
struct ShortcutsView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var store: ShortcutStore
    @Environment(\.moaiAccent) private var accent

    @State private var adding = false
    @State private var draftTitle = ""
    @State private var draftLink = ""
    @State private var hovered: UUID?
    @FocusState private var linkFieldFocused: Bool

    init(model: NotchViewModel) {
        self.model = model
        self.store = model.shortcuts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if adding {
                addRow
            }
            if store.shortcuts.isEmpty && !adding {
                VStack {
                    Spacer()
                    Text("Save the places you jump to — sites, apps, folders.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    Button {
                        beginAdding()
                    } label: {
                        Text("Add a shortcut")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(store.shortcuts) { shortcut in
                            chip(shortcut)
                        }
                        if !adding {
                            addChip
                        }
                    }
                }
            }
        }
        .animation(Theme.Motion.content, value: adding)
        .animation(Theme.Motion.content, value: store.shortcuts)
    }

    private func chip(_ shortcut: ShortcutStore.Shortcut) -> some View {
        Button {
            if store.open(shortcut) {
                model.collapse()
            }
        } label: {
            VStack(spacing: 6) {
                icon(for: shortcut)
                Text(shortcut.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .moaiCard(radius: Theme.Radius.row)
            .overlay(alignment: .topTrailing) {
                if hovered == shortcut.id {
                    Button {
                        store.remove(shortcut)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hovered = hovering ? shortcut.id : (hovered == shortcut.id ? nil : hovered)
        }
    }

    private func icon(for shortcut: ShortcutStore.Shortcut) -> some View {
        Group {
            if let fileIcon = ShortcutStore.fileIcon(for: shortcut.link) {
                Image(nsImage: fileIcon)
                    .resizable()
                    .frame(width: 26, height: 26)
            } else {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.14))
                    Text(String(shortcut.title.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 26, height: 26)
            }
        }
    }

    private var addChip: some View {
        Button {
            beginAdding()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 26, height: 26)
                Text("Add")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .strokeBorder(Theme.hairlineFaint, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("Name (optional)", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 110)
            TextField("github.com, /Applications/…, ~/folder", text: $draftLink)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($linkFieldFocused)
                .onSubmit(commitAdd)
            Button(action: commitAdd) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(draftLink.isEmpty ? Theme.textTertiary : accent)
            }
            .buttonStyle(.plain)
            .disabled(draftLink.isEmpty)
            Button {
                adding = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .moaiCard(radius: Theme.Radius.field)
    }

    private func beginAdding() {
        draftTitle = ""
        draftLink = ""
        adding = true
        linkFieldFocused = true
    }

    private func commitAdd() {
        guard !draftLink.isEmpty else { return }
        store.add(title: draftTitle, link: draftLink)
        adding = false
    }
}
