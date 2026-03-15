import SwiftUI

struct Shell: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            // Wallpaper layer (behind everything)
            if let wallpaperId = store.backgroundImage {
                wallpaperImage(for: wallpaperId)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(1.1)
                    .blur(radius: store.backgroundBlur)
                    .clipped()
                    .ignoresSafeArea()
            }

            // Main layout
            VStack(spacing: 0) {
                // Tab bar — full width, 36pt
                TabBarView()
                    .frame(height: Layout.tabBarHeight)

                // Body: sidebar + content
                HStack(spacing: 0) {
                    // Sidebar — 340pt
                    SidebarView()
                        .frame(width: Layout.sidebarWidth)

                    // Vertical divider between sidebar and content
                    theme.border.frame(width: 1)

                    // Content + status line
                    VStack(spacing: 0) {
                        // Content area
                        ZStack {
                            if store.hasWallpaper {
                                theme.bg.opacity(store.backgroundOpacity)
                            } else {
                                theme.bg
                            }
                            if store.activeProjectId == nil {
                                StartScreen()
                            } else {
                                // Placeholder for terminal content
                                if store.hasWallpaper {
                                    theme.bg.opacity(store.backgroundOpacity)
                                } else {
                                    theme.bg
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Horizontal divider above status line
                        theme.border.frame(height: 1)

                        // Status line — 32pt
                        StatusLine()
                            .frame(height: Layout.statusLineHeight)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .background(theme.bg)
            .font(Fonts.primary(size: 13))

            // Settings overlay
            if store.activeView == .settings {
                SettingsPage()
            }
        }
    }

    private func wallpaperImage(for id: String) -> Image {
        if let preset = WallpaperPreset.find(id) {
            let name = preset.filename
                .replacingOccurrences(of: ".jpg", with: "")
                .replacingOccurrences(of: ".png", with: "")
            return Image(name)
        } else {
            if let nsImage = NSImage(contentsOfFile: id) {
                return Image(nsImage: nsImage)
            }
            return Image(systemName: "photo")
        }
    }
}
