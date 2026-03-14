import SwiftUI

struct Shell: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — full width, 36pt
            TabBarView()
                .frame(height: Layout.tabBarHeight)

            // Body: sidebar + content
            HStack(spacing: 0) {
                // Sidebar — 340pt, border-right
                SidebarView()
                    .frame(width: Layout.sidebarWidth)

                // Content + status line
                VStack(spacing: 0) {
                    // Content area
                    ZStack {
                        theme.bg
                        if store.activeProjectId == nil {
                            StartScreen()
                        } else {
                            // Placeholder for terminal content
                            theme.bg
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Status line — 32pt
                    StatusLine()
                        .frame(height: Layout.statusLineHeight)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(theme.bg)
        .font(Fonts.primary(size: 13))
    }
}
