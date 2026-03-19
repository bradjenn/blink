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
        ShortcutEntry(action: "Close Window", keys: "⌘W"),
        ShortcutEntry(action: "Window 1–9", keys: "⌘1–9"),
    ]),
    ShortcutCategory(name: "Columns", shortcuts: [
        ShortcutEntry(action: "Move Window Left", keys: "⇧⌘H"),
        ShortcutEntry(action: "Move Window Right", keys: "⇧⌘L"),
        ShortcutEntry(action: "Absorb from Left", keys: "⇧⌘J"),
        ShortcutEntry(action: "Absorb from Right", keys: "⇧⌘K"),
        ShortcutEntry(action: "Expel Pane", keys: "⇧⌘E"),
        ShortcutEntry(action: "Resize Column", keys: "⌘R"),
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Keyboard Shortcuts")
                    .font(Fonts.primary(size: 18, weight: .bold))
                    .foregroundStyle(theme.text)

                ForEach(shortcutCategories) { category in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category.name)
                            .font(Fonts.primary(size: 14, weight: .medium))
                            .foregroundStyle(theme.text)
                            .padding(.bottom, 4)

                        ForEach(category.shortcuts) { shortcut in
                            HStack {
                                Text(shortcut.action)
                                    .font(Fonts.primary(size: 13))
                                    .foregroundStyle(theme.textMuted)
                                Spacer()
                                KeyCapBadge(keys: shortcut.keys)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
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
