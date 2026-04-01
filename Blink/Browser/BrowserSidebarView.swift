import SwiftUI

struct BrowserSidebarView: View {
    @Environment(\.theme) private var theme

    let paneState: BrowserPaneState
    let expanded: Bool
    let onHoverChange: (Bool) -> Void
    let onTogglePinned: () -> Void
    let onNewTab: () -> Void
    let onSelectTab: (String) -> Void
    let onCloseTab: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(theme.border)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(paneState.tabs) { browserTab in
                        BrowserSidebarTabRow(
                            browserTab: browserTab,
                            isSelected: paneState.selectedTab?.id == browserTab.id,
                            expanded: expanded,
                            onSelect: { onSelectTab(browserTab.id) },
                            onClose: { onCloseTab(browserTab.id) }
                        )
                    }
                }
                .padding(.horizontal, expanded ? 10 : 8)
                .padding(.vertical, 10)
            }
        }
        .frame(width: expanded ? Layout.browserSidebarWidth : Layout.browserRailWidth)
        .background(theme.bg.opacity(expanded ? 0.98 : 0.94))
        .animation(.snappy(duration: 0.2, extraBounce: 0), value: expanded)
        .onHover(perform: onHoverChange)
    }

    private var header: some View {
        VStack(spacing: 8) {
            if expanded {
                HStack(spacing: 8) {
                    Text("Browser")
                        .font(Fonts.primary(size: 12, weight: .bold))
                        .foregroundStyle(theme.text)

                    Spacer()

                    Text("\(paneState.tabs.count)")
                        .font(Fonts.primary(size: 11))
                        .foregroundStyle(theme.textDim)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(theme.bg2)
                        )
                }
            }

            HStack(spacing: 8) {
                sidebarButton(
                    systemName: "plus",
                    label: "New Browser Tab",
                    action: onNewTab
                )

                sidebarButton(
                    systemName: expanded ? "sidebar.left" : "sidebar.right",
                    label: expanded ? "Pin Browser Sidebar" : "Reveal Browser Sidebar",
                    action: onTogglePinned
                )
            }
        }
        .padding(.horizontal, expanded ? 10 : 8)
        .padding(.vertical, 10)
    }

    private func sidebarButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.bg2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(label)
    }
}

private struct BrowserSidebarTabRow: View {
    @Environment(\.theme) private var theme

    let browserTab: BrowserPaneTab
    let isSelected: Bool
    let expanded: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            glyph

            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    Text(browserTab.displayTitle)
                        .font(Fonts.primary(size: 12, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)

                    if let subtitle = browserTab.displaySubtitle {
                        Text(subtitle)
                            .font(Fonts.primary(size: 11))
                            .foregroundStyle(theme.textDim)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.textDim)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .opacity(isHovered ? 1 : 0.001)
            }
        }
        .padding(.horizontal, expanded ? 10 : 0)
        .padding(.vertical, expanded ? 10 : 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? theme.accent.opacity(0.14) : (isHovered ? theme.bg2 : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? theme.accent.opacity(0.45) : theme.border.opacity(expanded ? 1 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
        .pointerCursor()
    }

    private var glyph: some View {
        ZStack {
            Circle()
                .fill((isSelected ? theme.accent : theme.textMuted).opacity(0.16))
                .frame(width: expanded ? 22 : 20, height: expanded ? 22 : 20)

            Image(systemName: browserTab.state.isLoading ? "circle.dashed" : "globe")
                .font(.system(size: expanded ? 10 : 9, weight: .semibold))
                .foregroundStyle(isSelected ? theme.accent : theme.textDim)
        }
        .frame(maxWidth: expanded ? nil : .infinity)
    }
}
