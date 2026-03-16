import SwiftUI

struct SidebarProjectItem: View {
    @Environment(\.theme) private var theme

    let project: Project
    let isActive: Bool
    let terminalCount: Int
    let hasUnread: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false
    @State private var isRemoveHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Layout.sidebarItemGap) {
                // Project avatar
                ProjectFavicon(projectName: project.name, projectPath: project.path, size: 24)
                    .scaleEffect(isHovered ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)

                // Name + path
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(Fonts.primary(size: 15, weight: .medium))
                        .foregroundStyle(isActive ? theme.text : theme.textMuted)
                        .lineLimit(1)

                    Text(project.displayPath)
                        .font(Fonts.primary(size: 13))
                        .foregroundStyle(theme.textDim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Terminal count + pulse dot (pulses when unread activity)
                if terminalCount > 0 {
                    HStack(spacing: 4) {
                        if hasUnread {
                            PulseDot(color: theme.accent, glowColor: theme.accentGlow)
                        } else {
                            Circle()
                                .fill(theme.accent)
                                .frame(width: 6, height: 6)
                        }
                        if terminalCount > 1 {
                            Text("\(terminalCount)")
                                .font(Fonts.primary(size: 12))
                                .foregroundStyle(theme.accent)
                        }
                    }
                }

                // Remove button — only visible on hover
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isRemoveHovered ? theme.danger : theme.textDim)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Remove Project")
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.1), value: isHovered)
                .onHover { isRemoveHovered = $0 }
            }
        }
        .buttonStyle(.plain)
        .padding(Layout.sidebarItemPadding)
        .background(
            isActive
                ? theme.accent.opacity(0.04)
                : (isHovered ? theme.accent2.opacity(0.04) : Color.clear)
        )
        // Left border indicator — flush to edge, outside padding (matches CSS border-left)
        .overlay(alignment: .leading) {
            theme.accent
                .frame(width: Layout.sidebarItemBorderWidth)
                .opacity(isActive ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
        .pointerCursor()
    }
}

/// Animated pulsing dot indicating active terminals.
struct PulseDot: View {
    let color: Color
    let glowColor: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: glowColor, radius: 4, x: 0, y: 0)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
