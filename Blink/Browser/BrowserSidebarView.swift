import SwiftUI

struct BrowserSidebarView<HeaderContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    let paneState: BrowserPaneState
    let isPresented: Bool
    let isPinned: Bool
    let onHoverChange: (Bool) -> Void
    let onSelectTab: (String) -> Void
    let onCloseTab: (String) -> Void
    @ViewBuilder let headerContent: () -> HeaderContent

    var body: some View {
        VStack(spacing: 0) {
            headerContent()
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()
                .overlay(theme.border.opacity(0.9))

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(paneState.tabs) { browserTab in
                        BrowserSidebarTabRow(
                            browserTab: browserTab,
                            isSelected: paneState.selectedTab?.id == browserTab.id,
                            onSelect: { onSelectTab(browserTab.id) },
                            onClose: { onCloseTab(browserTab.id) }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .frame(width: Layout.browserSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.bg.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isPresented ? (isPinned ? 0.2 : 0.26) : 0), radius: 18, y: 10)
        .padding(.leading, 12)
        .padding(.vertical, 10)
        .offset(x: isPresented ? 0 : -(Layout.browserSidebarWidth + 24))
        .opacity(isPresented ? 1 : 0.001)
        .animation(reduceMotion ? .linear(duration: 0.01) : .snappy(duration: 0.22, extraBounce: 0), value: isPresented)
        .allowsHitTesting(isPresented)
        .onHover(perform: onHoverChange)
        .accessibilityHidden(!isPresented)
        .zIndex(2)
    }
}

private struct BrowserSidebarTabRow: View {
    @Environment(\.theme) private var theme

    let browserTab: BrowserPaneTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            glyph

            VStack(alignment: .leading, spacing: 3) {
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
            .allowsHitTesting(isHovered)
            .accessibilityHidden(!isHovered)
            .accessibilityLabel("Close \(browserTab.displayTitle)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? theme.accent.opacity(0.14) : (isHovered ? theme.bg2 : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? theme.accent.opacity(0.45) : theme.border.opacity(0.8), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(browserTab.displayTitle)
        .accessibilityValue(browserTab.displaySubtitle ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var glyph: some View {
        ZStack {
            Circle()
                .fill((isSelected ? theme.accent : theme.textMuted).opacity(0.16))
                .frame(width: 24, height: 24)

            Image(systemName: browserTab.state.isLoading ? "circle.dashed" : "globe")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? theme.accent : theme.textDim)
        }
    }
}
