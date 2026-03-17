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
                    store.showNewTabMenu.toggle()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isPlusHovered ? theme.text : theme.textDim)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("New Tab")
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
                .backgroundPopover(
                    isPresented: Binding(
                        get: { store.showNewTabMenu },
                        set: { store.showNewTabMenu = $0 }
                    )
                ) {
                    NewTabMenu(onAction: { action in
                        store.showNewTabMenu = false
                        guard let projectId = store.activeProjectId else { return }
                        switch action {
                        case .terminal:
                            store.openTab(projectId: projectId)
                        case .claude:
                            openOrFocusCommand(projectId: projectId, command: "claude", label: "Claude Code")
                        case .claudeYolo:
                            openOrFocusCommand(projectId: projectId, command: "claude --dangerously-skip-permissions", label: "Claude Code")
                        case .codex:
                            openOrFocusCommand(projectId: projectId, command: "codex", label: "Codex")
                        case .openCode:
                            openOrFocusCommand(projectId: projectId, command: "opencode", label: "Open Code")
                        case .lazygit:
                            openOrFocusCommand(projectId: projectId, command: "lazygit", label: "lazygit")
                        }
                    })
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openOrFocusCommand(projectId: String, command: String, label: String) {
        if let existing = store.projectTabs(for: projectId).first(where: { $0.command == command }) {
            store.setActiveTab(existing.id)
        } else {
            store.openTab(projectId: projectId, command: command, label: label)
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

enum NewTabAction {
    case terminal, claude, claudeYolo, codex, openCode, lazygit
}

struct NewTabMenu: View {
    @Environment(\.theme) private var theme
    let onAction: (NewTabAction) -> Void

    @State private var hoveredItem: String?
    @State private var yoloHovered = false

    var body: some View {
        VStack(spacing: 0) {
            menuRow("Terminal", icon: "terminal") { onAction(.terminal) }
            Divider().overlay(theme.border)

            HStack(spacing: 0) {
                menuRow("Claude Code", customIcon: ClaudeIcon()) { onAction(.claude) }

                Divider().overlay(theme.border).frame(height: 28)

                Button { onAction(.claudeYolo) } label: {
                    Text("Yolo")
                        .font(Fonts.primary(size: 11, weight: .medium))
                        .foregroundStyle(yoloHovered ? theme.text : theme.textDim)
                        .padding(.horizontal, 10)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(yoloHovered ? theme.accent.opacity(0.08) : Color.clear)
                .onHover { yoloHovered = $0 }
                .pointerCursor()
            }
            .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(theme.border)
            menuRow("Codex", customIcon: BundledSVGIcon(name: "codex-icon")) { onAction(.codex) }
            Divider().overlay(theme.border)
            menuRow("Open Code", customIcon: BundledSVGIcon(name: "opencode-icon")) { onAction(.openCode) }
            Divider().overlay(theme.border)
            menuRow("lazygit", icon: "point.3.connected.trianglepath.dotted") { onAction(.lazygit) }
        }
        .frame(width: 200)
        .background(theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 1))
        .padding(.top, 4)
    }

    private func menuRow(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        menuRow(label, iconView: AnyView(
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(hoveredItem == label ? theme.text : theme.textDim)
        ), action: action)
    }

    private func menuRow<Icon: View>(_ label: String, customIcon: Icon, action: @escaping () -> Void) -> some View {
        menuRow(label, iconView: AnyView(
            customIcon
                .frame(width: 14, height: 14)
        ), action: action)
    }

    private func menuRow(_ label: String, iconView: AnyView, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                iconView.frame(width: 16)
                Text(label)
                    .font(Fonts.primary(size: 13))
                    .foregroundStyle(hoveredItem == label ? theme.text : theme.textMuted)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hoveredItem == label ? theme.accent.opacity(0.08) : Color.clear)
        .onHover { hoveredItem = $0 ? label : nil }
        .pointerCursor()
    }
}

struct BundledSVGIcon: View {
    let name: String

    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        }
    }
}

struct ClaudeIcon: View {
    var body: some View {
        BundledSVGIcon(name: "claude-icon")
    }
}
