import SwiftUI

enum Layout {
    // Sidebar
    static let sidebarWidth: CGFloat = 340
    static let sidebarCollapsedWidth: CGFloat = 50
    static let sidebarItemPadding = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 12)
    static let sidebarItemBorderWidth: CGFloat = 3
    static let sidebarItemGap: CGFloat = 10        // gap-2.5
    static let sidebarHeaderPadding = EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16)
    static let sidebarSettingsHeight: CGFloat = 32

    // Tab bar
    static let tabBarHeight: CGFloat = 36
    static let tabBarLogoPaddingLeft: CGFloat = 78 // macOS traffic lights offset
    static let tabPillPaddingH: CGFloat = 14

    // Status line
    static let statusLineHeight: CGFloat = 32
    static let statusLinePaddingH: CGFloat = 14

    // Window
    static let windowMinWidth: CGFloat = 800
    static let windowMinHeight: CGFloat = 500
    static let windowDefaultWidth: CGFloat = 1200
    static let windowDefaultHeight: CGFloat = 750
}

enum Fonts {
    /// Returns the correct JetBrains Mono variant name for a given weight.
    /// SwiftUI's `.weight()` does NOT work with custom fonts — you must use the
    /// exact PostScript font name for each weight variant.
    static func primary(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold:
            name = "JetBrainsMono-Bold"
        case .medium:
            name = "JetBrainsMono-Medium"
        case .semibold:
            name = "JetBrainsMono-SemiBold"
        case .light:
            name = "JetBrainsMono-Light"
        default:
            name = "JetBrainsMono-Regular"
        }
        return .custom(name, size: size)
    }
}
