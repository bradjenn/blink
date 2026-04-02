import SwiftUI

enum Layout {
    // Sidebar
    static let sidebarWidth: CGFloat = 324
    static let sidebarItemPadding = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    static let sidebarItemBorderWidth: CGFloat = 3
    static let sidebarItemGap: CGFloat = 10        // gap-2.5
    static let sidebarHeaderPadding = EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
    static let sidebarSettingsHeight: CGFloat = 32

    // Tab bar
    static let tabBarHeight: CGFloat = 36
    static let tabBarLogoPaddingLeft: CGFloat = 78 // macOS traffic lights offset
    static let tabPillPaddingH: CGFloat = 14

    // Workspace
    static let workspacePaddingH: CGFloat = 10
    static let workspacePaddingV: CGFloat = 8
    static let workspaceColumnSpacing: CGFloat = 10
    static let workspaceColumnMinWidth: CGFloat = 420
    static let workspaceColumnMaxWidth: CGFloat = 4000
    static let workspaceColumnDefaultFraction: CGFloat = 0.5
    static let workspaceColumnPresets: [CGFloat] = [1.0 / 3.0, 0.5, 2.0 / 3.0, 1.0]
    static let browserSurfaceCornerRadius: CGFloat = 6
    static let browserSidebarHotspotWidth: CGFloat = 2
    static let browserSidebarFloatingInset: CGFloat = 10
    static let browserSidebarHoverBridgeWidth: CGFloat = workspacePaddingH + browserSidebarFloatingInset
    static let browserSidebarWidth: CGFloat = 296

    // Overview (Niri-style horizontal strip)
    static let overviewPadding: CGFloat = 40
    static let overviewGap: CGFloat = 16
    static let overviewThumbnailHeightRatio: CGFloat = 0.50  // % of viewport height
    static let overviewCornerRadius: CGFloat = 8

    // Column panes
    static let columnPaneDividerHeight: CGFloat = 1

    // Chat
    static let chatContentMaxWidth: CGFloat = 820
    static let chatHistoryRailWidth: CGFloat = 280
    static let chatHistoryCollapseThreshold: CGFloat = 760

    // Status line
    static let statusLineHeight: CGFloat = 30

    // Window
    static let windowMinWidth: CGFloat = 800
    static let windowMinHeight: CGFloat = 500
    static let windowDefaultWidth: CGFloat = 1200
    static let windowDefaultHeight: CGFloat = 750
}

/// How the viewport tracks the focused column, ported from Niri's centering strategies.
enum FocusCenteringMode: String, CaseIterable {
    /// Scroll minimum amount to make active column fully visible (current behavior).
    case never
    /// Center the active column when adjacent columns don't fit in the viewport.
    case onOverflow
    /// Always center the active column in the viewport.
    case always
}

enum Fonts {
    static let defaultFamily = "MesloLGS Nerd Font Mono"

    /// Returns a font from the given family (or the bundled MesloLGS default).
    /// For the default family, exact PostScript names are used because
    /// SwiftUI's `.weight()` does NOT work with custom fonts.
    static func primary(size: CGFloat, weight: Font.Weight = .regular, family: String? = nil) -> Font {
        let resolvedFamily = family ?? defaultFamily
        if resolvedFamily == defaultFamily {
            let name = weight == .bold ? "MesloLGSNFM-Bold" : "MesloLGSNFM-Regular"
            return .custom(name, size: size)
        }
        return .custom(resolvedFamily, size: size).weight(weight)
    }
}
