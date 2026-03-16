import SwiftUI

/// Logo area — sits in the top bar left section.
struct TabBarLogoArea: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    @State private var isToggleHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                store.toggleSidebar()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(isToggleHovered ? theme.text : theme.textDim)
                    .frame(width: 44, height: Layout.tabBarHeight)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Toggle Sidebar")
            .buttonStyle(.plain)
            .onHover { isToggleHovered = $0 }
            .pointerCursor()

            Text("BLINK")
                .font(Fonts.primary(size: 11, weight: .bold).leading(.tight))
                .tracking(1.65)
                .textCase(.uppercase)
                .foregroundStyle(theme.textDim)
                .lineLimit(1)
                .padding(.leading, 4)
        }
        .frame(maxHeight: .infinity, alignment: .leading)
    }
}

/// Tabs area — sits in the top bar right section.
struct TabBarTabsArea: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager

    @State private var isPlusHovered = false

    private var projectTabs: [AppTab] {
        guard let id = store.activeProjectId else { return [] }
        return store.projectTabs(for: id)
    }

    var body: some View {
        HStack(spacing: 0) {
            if store.activeProjectId != nil {
                HStack(spacing: 0) {
                    ForEach(projectTabs) { tab in
                        TabPill(
                            tab: tab,
                            isActive: store.activeTabId == tab.id,
                            onSelect: { store.setActiveTab(tab.id) },
                            onClose: {
                                surfaceManager.destroySurface(tabId: tab.id)
                                store.closeTab(tab.id)
                            }
                        )
                    }
                }

                Button {
                    guard let projectId = store.activeProjectId else { return }
                    store.openTab(projectId: projectId)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isPlusHovered ? theme.text : theme.textDim)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("New Terminal")
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isPlusHovered ? theme.accent.opacity(0.1) : theme.border.opacity(0.3))
                )
                .scaleEffect(isPlusHovered ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isPlusHovered)
                .padding(.leading, 6)
                .onHover { hovering in
                    isPlusHovered = hovering
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TabPill: View {
    @Environment(\.theme) private var theme

    let tab: AppTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false
    @State private var isCloseHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(tab.label)
                    .font(Fonts.primary(size: 12).leading(.tight))
                    .foregroundStyle(isActive || isHovered ? theme.text : theme.textMuted)
                    .lineLimit(1)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isCloseHovered ? theme.danger : theme.textDim)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close Tab")
                .buttonStyle(.plain)
                .background(
                    isCloseHovered
                        ? theme.danger.opacity(0.15)
                        : Color.clear
                )
                .clipShape(.rect(cornerRadius: 3))
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.1), value: isHovered)
                .onHover { isCloseHovered = $0 }
            }
            .padding(.horizontal, Layout.tabPillPaddingH)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isActive || isHovered
                ? Color.white.opacity(0.02)
                : Color.clear
        )
        .overlay(alignment: .bottom) {
            if isActive {
                theme.accent.frame(height: 2)
            }
        }
        .onHover { isHovered = $0 }
        .pointerCursor()
    }
}
