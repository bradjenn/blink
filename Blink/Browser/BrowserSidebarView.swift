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

    private var sidebarOffset: CGFloat {
        if isPinned {
            return isPresented ? 0 : -Layout.browserSidebarWidth
        }

        return isPresented ? 0 : -(Layout.browserSidebarWidth + 24)
    }

    private var transitionAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .snappy(duration: 0.24, extraBounce: 0)
    }

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
        .background(backgroundSurface)
        .overlay(overlaySurface)
        .shadow(color: Color.black.opacity(isPresented && !isPinned ? 0.26 : 0), radius: 18, y: 10)
        .padding(.leading, isPinned ? 0 : 12)
        .padding(.vertical, isPinned ? 0 : 10)
        .offset(x: sidebarOffset)
        .opacity(isPresented ? 1 : 0.001)
        .animation(transitionAnimation, value: isPresented)
        .animation(transitionAnimation, value: isPinned)
        .allowsHitTesting(isPresented)
        .onHover(perform: onHoverChange)
        .accessibilityHidden(!isPresented)
        .zIndex(2)
    }

    @ViewBuilder
    private var backgroundSurface: some View {
        if isPinned {
            theme.bg.opacity(0.98)
        } else {
            RoundedRectangle(cornerRadius: Layout.browserSurfaceCornerRadius, style: .continuous)
                .fill(theme.bg.opacity(0.97))
        }
    }

    @ViewBuilder
    private var overlaySurface: some View {
        if isPinned {
            Rectangle()
                .fill(theme.border.opacity(0.95))
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            RoundedRectangle(cornerRadius: Layout.browserSurfaceCornerRadius, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
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
            favicon

            Text(browserTab.displayTitle)
                .font(Fonts.primary(size: 12, weight: isSelected ? .bold : .regular))
                .foregroundStyle(theme.text)
                .lineLimit(1)

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
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? theme.bg2.opacity(0.9) : (isHovered ? theme.bg2.opacity(0.55) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(browserTab.displayTitle)
        .accessibilityValue(browserTab.host ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var favicon: some View {
        if let faviconURL = browserTab.faviconURL {
            AsyncImage(url: faviconURL, transaction: .init(animation: .none)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                default:
                    faviconFallback
                }
            }
            .frame(width: 16, height: 16)
        } else {
            faviconFallback
        }
    }

    private var faviconFallback: some View {
        Image(systemName: browserTab.state.isLoading ? "circle.dashed" : "globe")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isSelected ? theme.text : theme.textDim)
            .frame(width: 16, height: 16)
    }
}
