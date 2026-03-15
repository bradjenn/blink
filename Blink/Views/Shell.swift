import SwiftUI

struct Shell: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            // Wallpaper layer (behind everything, pinned to window bounds)
            if let wallpaperId = store.backgroundImage {
                GeometryReader { geo in
                    wallpaperImage(for: wallpaperId)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(1.1)
                        .blur(radius: store.backgroundBlur)
                        .clipped()
                }
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
                            // Background layer
                            if store.hasWallpaper {
                                theme.bg.opacity(store.backgroundOpacity)
                            } else {
                                theme.bg
                            }

                            if store.activeView == .settings {
                                SettingsPage()
                            } else if store.activeProjectId == nil {
                                StartScreen()
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
            .background(store.hasWallpaper ? Color.clear : theme.bg)
            .font(Fonts.primary(size: 13))
        }
    }

    /// Load wallpaper image from bundle (preset) or file path (custom).
    private func wallpaperImage(for id: String) -> Image {
        if let preset = WallpaperPreset.find(id),
           let url = Bundle.main.url(forResource: preset.filename.replacingOccurrences(of: ".\(preset.filename.split(separator: ".").last ?? "")", with: ""),
                                     withExtension: String(preset.filename.split(separator: ".").last ?? "")),
           let nsImage = NSImage(contentsOf: url) {
            return Image(nsImage: nsImage)
        } else if !id.hasPrefix("preset:"), let nsImage = NSImage(contentsOfFile: id) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "photo")
    }
}
