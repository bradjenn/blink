import SwiftUI

struct SettingsPage: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let ghosttyApp: GhosttyApp

    enum SettingsTab: String, CaseIterable {
        case appearance = "Appearance"
        case terminal = "Terminal"
        case ai = "AI"
        case keyboardShortcuts = "Keyboard Shortcuts"
    }

    @State private var selectedTab: SettingsTab = .appearance
    @State private var isCloseHovered = false
    @State private var closePressed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 0) {
                // Nav sidebar — sits to the left of the content max-width
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        SettingsTabButton(
                            label: tab.rawValue,
                            badgeText: tab == .ai ? "New" : nil,
                            isActive: selectedTab == tab,
                            action: { selectedTab = tab }
                        )
                    }
                }
                .frame(width: 180)
                .padding(.top, 20)
                .padding(.leading, 16)
                .padding(.trailing, 12)

                // Content area — fixed max width, scrollbar hugs right edge
                switch selectedTab {
                case .appearance:
                    AppearanceSettings(ghosttyApp: ghosttyApp)
                case .terminal:
                    TerminalSettings(ghosttyApp: ghosttyApp)
                case .ai:
                    AISettings()
                case .keyboardShortcuts:
                    KeyboardShortcutsSettings()
                }
            }
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Close button — top left
            Button(action: {
                withAnimation(.easeOut(duration: 0.12)) { closePressed = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    store.toggleSettings()
                    closePressed = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isCloseHovered ? theme.text : theme.textMuted)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(isCloseHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isCloseHovered ? theme.textMuted.opacity(0.4) : theme.border,
                                lineWidth: 1
                            )
                    )
                    .scaleEffect(closePressed ? 0.85 : 1.0)
                    .opacity(closePressed ? 0.6 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovered = $0 }
            .pointerCursor()
            .animation(.easeOut(duration: 0.15), value: isCloseHovered)
            .padding(.leading, 10)
            .padding(.top, 10)
        }
        .font(Fonts.primary(size: 13, family: store.uiFontFamily))
    }
}

private struct SettingsTabButton: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let label: String
    let badgeText: String?
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(Fonts.primary(size: 14, family: store.uiFontFamily))
                    .foregroundStyle(isActive ? theme.text : isHovered ? theme.text : theme.textMuted)

                if let badgeText {
                    Text(badgeText)
                        .font(Fonts.primary(size: 10, weight: .medium, family: store.uiFontFamily))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(theme.accent.opacity(0.14))
                        )
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.06) : isHovered ? Color.white.opacity(0.03) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
