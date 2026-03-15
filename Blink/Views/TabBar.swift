import SwiftUI

/// Logo area — sits in the left sidebar column header.
struct TabBarLogoArea: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    @State private var isToggleHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.sidebarVisible.toggle()
                }
            }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(isToggleHovered ? theme.text : theme.textDim)
                    .frame(width: Layout.sidebarCollapsedWidth, height: Layout.tabBarHeight)
            }
            .buttonStyle(.plain)
            .onHover { isToggleHovered = $0 }

            if store.sidebarVisible {
                Text("BLINK")
                    .font(Fonts.primary(size: 11, weight: .bold).leading(.tight))
                    .tracking(1.65)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.textDim)
                    .lineLimit(1)
                    .padding(.leading, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Tabs area — sits in the right content column header.
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

                Button(action: {
                    guard let projectId = store.activeProjectId else { return }
                    store.openTab(projectId: projectId)
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isPlusHovered ? theme.accent : theme.textDim)
                        .frame(width: Layout.tabBarHeight, height: Layout.tabBarHeight)
                }
                .buttonStyle(.plain)
                .onHover { isPlusHovered = $0 }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            store.hasWallpaper
                ? AnyShapeStyle(theme.bg.opacity(store.backgroundOpacity))
                : AnyShapeStyle(theme.bg)
        )
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
                        .padding(2)
                        .background(
                            isCloseHovered
                                ? theme.danger.opacity(0.15)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
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
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}
