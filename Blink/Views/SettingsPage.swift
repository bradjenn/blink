import SwiftUI

struct SettingsPage: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let ghosttyApp: GhosttyApp

    enum SettingsTab: String, CaseIterable {
        case appearance = "Appearance"
        case terminal = "Terminal"
        case keyboardShortcuts = "Keyboard Shortcuts"
    }

    @State private var selectedTab: SettingsTab = .appearance
    @State private var isBackHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: back button — aligned over nav tabs
            Button(action: { store.setActiveView(.projects) }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                    Text("Settings")
                        .font(Fonts.primary(size: 16, weight: .bold))
                }
                .foregroundStyle(isBackHovered ? theme.text : theme.textMuted)
            }
            .buttonStyle(.plain)
            .onHover { isBackHovered = $0 }
            .pointerCursor()
            .padding(.leading, 32)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Body: nav + content fills available space
            HStack(alignment: .top, spacing: 0) {
                // Nav sidebar
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        let isActive = selectedTab == tab
                        let isDisabled = tab != .appearance

                        Button(action: { if !isDisabled { selectedTab = tab } }) {
                            Text(tab.rawValue)
                                .font(Fonts.primary(size: 14))
                                .foregroundStyle(
                                    isDisabled ? theme.textDim :
                                    isActive ? theme.text : theme.textMuted
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    isActive ? Color.white.opacity(0.06) : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(isDisabled)
                        .pointerCursor()
                    }
                }
                .frame(width: 200)
                .padding(.leading, 32)
                .padding(.trailing, 16)

                // Content area — fills remaining space
                switch selectedTab {
                case .appearance:
                    AppearanceSettings(ghosttyApp: ghosttyApp)
                case .terminal:
                    Text("Terminal settings coming soon")
                        .font(Fonts.primary(size: 14))
                        .foregroundStyle(theme.textDim)
                        .padding(32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .keyboardShortcuts:
                    Text("Keyboard shortcuts coming soon")
                        .font(Fonts.primary(size: 14))
                        .foregroundStyle(theme.textDim)
                        .padding(32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
