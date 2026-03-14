import SwiftUI

@main
struct BApp: App {
    @State private var themeManager = ThemeManager()
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            Shell()
                .environment(store)
                .environment(\.theme, themeManager.activeTheme)
                .frame(
                    minWidth: Layout.windowMinWidth,
                    minHeight: Layout.windowMinHeight
                )
                .preferredColorScheme(.dark)
        }
        .defaultSize(
            width: Layout.windowDefaultWidth,
            height: Layout.windowDefaultHeight
        )
    }
}
