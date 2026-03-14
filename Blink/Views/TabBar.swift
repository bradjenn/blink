import SwiftUI

struct TabBarView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    @State private var isPlusHovered = false

    private var projectTabs: [AppTab] {
        guard let id = store.activeProjectId else { return [] }
        return store.projectTabs(for: id)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Logo area — width matches sidebar
            HStack {
                Text("KRUX")
                    .font(Fonts.primary(size: 11, weight: .bold))
                    .tracking(1.65) // 0.15em * 11pt = 1.65pt
                    .textCase(.uppercase)
                    .foregroundStyle(theme.textDim)
            }
            .frame(width: Layout.sidebarWidth, alignment: .leading)
            .padding(.leading, Layout.tabBarLogoPaddingLeft)
            .overlay(alignment: .trailing) {
                theme.border.frame(width: 1)
            }

            // Tab pills — scrollable
            if store.activeProjectId != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(projectTabs) { tab in
                            TabPill(
                                tab: tab,
                                isActive: store.activeTabId == tab.id,
                                onSelect: { store.setActiveTab(tab.id) },
                                onClose: { store.closeTab(tab.id) }
                            )
                        }
                    }
                }

                // Plus button
                Button(action: { /* new tab — future */ }) {
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
        .background(theme.bg2)
        .overlay(alignment: .bottom) {
            theme.border.frame(height: 1)
        }
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
        HStack(spacing: 6) {
            Text(tab.label)
                .font(Fonts.primary(size: 12))
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
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
    }
}
