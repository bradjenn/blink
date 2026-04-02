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
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 9)

            Divider()
                .overlay(theme.border.opacity(0.9))

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(paneState.tabs) { browserTab in
                        BrowserSidebarTabRow(
                            browserTab: browserTab,
                            isSelected: paneState.selectedTab?.id == browserTab.id,
                            onSelect: { onSelectTab(browserTab.id) },
                            onClose: { onCloseTab(browserTab.id) }
                        )
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 7)
            }
        }
        .frame(width: Layout.browserSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(backgroundSurface)
        .overlay(overlaySurface)
        .shadow(color: Color.black.opacity(isPresented && !isPinned ? 0.26 : 0), radius: 18, y: 10)
        .padding(.leading, isPinned ? 0 : Layout.browserSidebarFloatingInset)
        .padding(.vertical, isPinned ? 0 : 9)
        .offset(x: sidebarOffset)
        .opacity(isPresented ? 1 : 0.001)
        .animation(transitionAnimation, value: isPresented)
        .animation(transitionAnimation, value: isPinned)
        .allowsHitTesting(isPresented)
        .onHover { isHovered in
            guard isPresented else { return }
            onHoverChange(isHovered)
        }
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

    private var rowFill: Color {
        if isSelected {
            return theme.bg2
        }
        if isHovered {
            return theme.bg2
        }
        return .clear
    }

    private var titleFadeColor: Color {
        if isSelected || isHovered {
            return rowFill
        }
        return theme.bg
    }

    private var closeButtonBackground: Color {
        if isSelected || isHovered {
            return theme.bg2
        }
        return theme.bg2
    }

    var body: some View {
        HStack(spacing: 8) {
            favicon

            titleLabel
        }
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowFill)
        )
        .overlay(alignment: .trailing) {
            if isHovered {
                closeButton
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(browserTab.displayTitle)
        .accessibilityValue(browserTab.host ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var titleLabel: some View {
        GeometryReader { geometry in
            Text(browserTab.displayTitle)
                .font(Fonts.primary(size: 11.5, weight: isSelected ? .bold : .regular))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: true, vertical: false)
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .leading
                )
                .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 20)
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [Color.clear, titleFadeColor],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: isHovered ? 34 : 16)
            .allowsHitTesting(false)
        }
        .animation(.snappy(duration: 0.18, extraBounce: 0), value: isHovered)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.textDim)
                .frame(width: 28)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(closeButtonBackground)
                )
        }
        .buttonStyle(.plain)
        .frame(width: 28)
        .frame(maxHeight: .infinity)
        .pointerCursor()
        .accessibilityLabel("Close \(browserTab.displayTitle)")
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
            .frame(width: 14, height: 14)
        } else {
            faviconFallback
        }
    }

    private var faviconFallback: some View {
        Image(systemName: browserTab.state.isLoading ? "circle.dashed" : "globe")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isSelected ? theme.text : theme.textDim)
            .frame(width: 14, height: 14)
    }
}
