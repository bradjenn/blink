import SwiftUI
import AppKit

/// Logo area — sits in the top bar left section.
struct TabBarLogoArea: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    @State private var isToggleHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggleSidebar) {
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

    private func toggleSidebar() {
        store.toggleSidebar()
    }
}

/// Workspace toolbar — shows project and focused window context.
struct TabBarTabsArea: View {
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
    }
}

enum NewTabAction {
    case terminal, claude, claudeYolo, codex, openCode, lazygit, yazi, neovim
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

                Button(action: runClaudeYolo) {
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
            Divider().overlay(theme.border)
            menuRow("Yazi", icon: "folder") { onAction(.yazi) }
            Divider().overlay(theme.border)
            menuRow("Neovim", icon: "chevron.left.forwardslash.chevron.right") { onAction(.neovim) }
        }
        .frame(width: 200)
        .background(theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 1))
        .padding(.top, 4)
    }

    private func runClaudeYolo() {
        onAction(.claudeYolo)
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
