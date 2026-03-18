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
    static let workspaceFocusedColumnPeek: CGFloat = 0

    // Status line
    static let statusLineHeight: CGFloat = 30

    // Window
    static let windowMinWidth: CGFloat = 800
    static let windowMinHeight: CGFloat = 500
    static let windowDefaultWidth: CGFloat = 1200
    static let windowDefaultHeight: CGFloat = 750
}

enum Fonts {
    /// Returns the correct MesloLGS Nerd Font Mono variant for a given weight.
    /// SwiftUI's `.weight()` does NOT work with custom fonts — you must use the
    /// exact PostScript font name for each weight variant.
    static func primary(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold:
            name = "MesloLGSNFM-Bold"
        default:
            name = "MesloLGSNFM-Regular"
        }
        return .custom(name, size: size)
    }
}
