import SwiftUI

struct BrowserSidebarView<HeaderContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    private let pinnedTileSize: CGFloat = 48
    private let pinnedGridColumnCount = 5
    private let pinnedGridSpacing: CGFloat = 8
    private let pinnedTileCornerRadius: CGFloat = 10

    let paneState: BrowserPaneState
    let isPresented: Bool
    let isPinned: Bool
    let onHoverChange: (Bool) -> Void
    let onSelectTab: (String) -> Void
    let onTogglePin: (String) -> Void
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
                .padding(.bottom, 8)
                .zIndex(2)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    if !paneState.pinnedTabs.isEmpty {
                        pinnedTabsGrid
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)

                        Divider()
                            .overlay(theme.border.opacity(0.9))
                    }

                    LazyVStack(spacing: 4) {
                        if !paneState.unpinnedTabs.isEmpty {
                            ForEach(paneState.unpinnedTabs) { browserTab in
                                BrowserSidebarTabRow(
                                    browserTab: browserTab,
                                    isSelected: paneState.selectedTab?.id == browserTab.id,
                                    onSelect: { onSelectTab(browserTab.id) },
                                    onTogglePin: { onTogglePin(browserTab.id) },
                                    onClose: { onCloseTab(browserTab.id) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.top, 7)
                }
            }
            .zIndex(1)
        }
        .frame(width: Layout.browserSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(backgroundSurface)
        .overlay(overlaySurface)
        .clipShape(.rect(cornerRadius: isPinned ? 0 : Layout.browserSurfaceCornerRadius))
        .compositingGroup()
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
            Color.clear
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

    private var pinnedTabsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: pinnedGridSpacing, verticalSpacing: pinnedGridSpacing) {
            ForEach(Array(stride(from: 0, to: paneState.pinnedTabs.count, by: pinnedGridColumnCount)), id: \.self) { startIndex in
                GridRow {
                    ForEach(Array(paneState.pinnedTabs[startIndex..<min(startIndex + pinnedGridColumnCount, paneState.pinnedTabs.count)])) { browserTab in
                        BrowserPinnedTabTile(
                            browserTab: browserTab,
                            isSelected: paneState.selectedTab?.id == browserTab.id,
                            onSelect: { onSelectTab(browserTab.id) },
                            onTogglePin: { onTogglePin(browserTab.id) },
                            onClose: { onCloseTab(browserTab.id) },
                            tileSize: pinnedTileSize,
                            cornerRadius: pinnedTileCornerRadius
                        )
                    }

                    ForEach(0..<max(0, pinnedGridColumnCount - (paneState.pinnedTabs.count - startIndex)), id: \.self) { _ in
                        Color.clear
                            .frame(width: pinnedTileSize, height: pinnedTileSize)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BrowserPinnedTabTile: View {
    @Environment(\.theme) private var theme

    let browserTab: BrowserPaneTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onClose: () -> Void
    let tileSize: CGFloat
    let cornerRadius: CGFloat

    @State private var isHovered = false

    private var tileBackground: Color {
        if isSelected {
            return theme.accent.opacity(0.2)
        }

        if isHovered {
            return theme.bg2
        }

        return theme.bg2.opacity(0.92)
    }

    private var tileBorder: Color {
        if isSelected {
            return theme.accent.opacity(0.95)
        }

        if isHovered {
            return theme.border.opacity(0.9)
        }

        return theme.border.opacity(0.55)
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tileBackground)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tileBorder, lineWidth: isSelected ? 2 : 1)

                favicon
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isSelected {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 7, height: 7)
                        .padding(8)
                }
            }
            .frame(width: tileSize, height: tileSize)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(browserTab.displayTitle)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .contextMenu {
            Button("Unpin Tab", action: onTogglePin)
            Button("Close Tab", action: onClose)
        }
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
            .frame(width: 18, height: 18)
        } else {
            faviconFallback
        }
    }

    private var faviconFallback: some View {
        Image(systemName: browserTab.state.isLoading ? "circle.dashed" : "globe")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? theme.accent : theme.text)
            .frame(width: 18, height: 18)
    }
}

private struct BrowserSidebarTabRow: View {
    @Environment(\.theme) private var theme
    private let rowCornerRadius: CGFloat = 8
    private let miniButtonCornerRadius: CGFloat = 6

    let browserTab: BrowserPaneTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
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
        return theme.bg2
    }

    private var trailingButtonCount: CGFloat {
        isHovered ? 2 : (browserTab.isPinned ? 1 : 0)
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
            RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                .fill(rowFill)
        )
        .overlay(alignment: .trailing) {
            HStack(spacing: 4) {
                if browserTab.isPinned || isHovered {
                    pinButton
                        .transition(.opacity)
                }

                if isHovered {
                    closeButton
                        .transition(.opacity)
                }
            }
            .padding(.trailing, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .contextMenu {
            Button(browserTab.isPinned ? "Unpin Tab" : "Pin Tab", action: onTogglePin)
            Button("Close Tab", action: onClose)
        }
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
            .frame(width: max(16, 16 + (trailingButtonCount * 28)))
            .allowsHitTesting(false)
        }
        .animation(.snappy(duration: 0.18, extraBounce: 0), value: isHovered)
    }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: browserTab.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(browserTab.isPinned ? theme.accent : theme.textDim)
                .frame(width: 28)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: miniButtonCornerRadius, style: .continuous)
                        .fill(closeButtonBackground)
                )
        }
        .buttonStyle(.plain)
        .frame(width: 28)
        .frame(maxHeight: .infinity)
        .pointerCursor()
        .accessibilityLabel(browserTab.isPinned ? "Unpin \(browserTab.displayTitle)" : "Pin \(browserTab.displayTitle)")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.textDim)
                .frame(width: 28)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: miniButtonCornerRadius, style: .continuous)
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
