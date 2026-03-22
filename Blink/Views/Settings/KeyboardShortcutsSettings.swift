import SwiftUI

private struct ShortcutEntry: Identifiable {
    let id = UUID()
    let action: String
    let keys: String
}

private struct ShortcutCategory: Identifiable {
    let id = UUID()
    let name: String
    let shortcuts: [ShortcutEntry]
}

private let shortcutCategories: [ShortcutCategory] = [
    ShortcutCategory(name: "Navigation", shortcuts: [
        ShortcutEntry(action: "Focus Left", keys: "⌘H"),
        ShortcutEntry(action: "Focus Right", keys: "⌘L"),
        ShortcutEntry(action: "Focus Down", keys: "⌘J"),
        ShortcutEntry(action: "Focus Up", keys: "⌘K"),
    ]),
    ShortcutCategory(name: "Windows", shortcuts: [
        ShortcutEntry(action: "New Window", keys: "⌘T"),
        ShortcutEntry(action: "Split Below", keys: "⇧⌘_"),
        ShortcutEntry(action: "Split Right", keys: "⇧⌘|"),
        ShortcutEntry(action: "Close Window", keys: "⌘W"),
        ShortcutEntry(action: "Window 1–9", keys: "⌘1–9"),
    ]),
    ShortcutCategory(name: "Columns", shortcuts: [
        ShortcutEntry(action: "Move Window Left", keys: "⇧⌘H"),
        ShortcutEntry(action: "Move Window Right", keys: "⇧⌘L"),
        ShortcutEntry(action: "Absorb from Left", keys: "⇧⌘J"),
        ShortcutEntry(action: "Absorb from Right", keys: "⇧⌘K"),
        ShortcutEntry(action: "Expel Pane", keys: "⇧⌘E"),
        ShortcutEntry(action: "Increase Column Size", keys: "⌘]"),
        ShortcutEntry(action: "Decrease Column Size", keys: "⌘["),
        ShortcutEntry(action: "Maximize Column", keys: "⌘F"),
    ]),
    ShortcutCategory(name: "Workspace", shortcuts: [
        ShortcutEntry(action: "Toggle Sidebar", keys: "⌘B"),
        ShortcutEntry(action: "Overview", keys: "⌘O"),
        ShortcutEntry(action: "Open Git", keys: "⌘G"),
    ]),
    ShortcutCategory(name: "App", shortcuts: [
        ShortcutEntry(action: "Settings", keys: "⌘,"),
        ShortcutEntry(action: "Switch Project", keys: "⌘P"),
        ShortcutEntry(action: "Switch Theme", keys: "⇧⌘T"),
    ]),
]

struct KeyboardShortcutsSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Keyboard Shortcuts")
                    .font(Fonts.primary(size: 18, weight: .bold, family: store.uiFontFamily))
                    .foregroundStyle(theme.text)

                ForEach(shortcutCategories) { category in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(Fonts.primary(size: 14, weight: .medium, family: store.uiFontFamily))
                            .foregroundStyle(theme.text)
                            .padding(.bottom, 6)

                        ForEach(category.shortcuts) { shortcut in
                            ShortcutRow(shortcut: shortcut, fontFamily: store.uiFontFamily)
                        }
                    }
                }

                Spacer()
            }
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
}

private struct ShortcutRow: View {
    @Environment(\.theme) private var theme
    let shortcut: ShortcutEntry
    let fontFamily: String

    @State private var isHovered = false

    var body: some View {
        HStack {
            Text(shortcut.action)
                .font(Fonts.primary(size: 13, family: fontFamily))
                .foregroundStyle(isHovered ? theme.text : theme.textMuted)
            Spacer()
            KeyCapBadge(keys: shortcut.keys)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.04) : .clear)
        )
        .onHover { isHovered = $0 }
        .frame(maxWidth: .infinity)
    }
}

private struct KeyCapBadge: View {
    @Environment(\.theme) private var theme
    let keys: String

    var body: some View {
        Text(keys)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }
}
