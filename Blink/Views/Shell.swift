import SwiftUI
import GhosttyKit

struct Shell: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let ghosttyApp: GhosttyApp

    private var sidebarWidth: CGFloat {
        store.sidebarVisible ? Layout.sidebarWidth : Layout.sidebarCollapsedWidth
    }

    var body: some View {
        ZStack {
            // Wallpaper layer
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

            // Main layout — two columns with a single full-height divider
            HStack(spacing: 0) {
                // LEFT COLUMN: logo header + sidebar
                VStack(spacing: 0) {
                    // Logo header (same height as tab bar)
                    TabBarLogoArea()
                        .frame(height: Layout.tabBarHeight)

                    // Horizontal border under logo
                    theme.border.frame(height: 1)

                    // Sidebar content
                    SidebarView()
                }
                .frame(width: sidebarWidth)
                .background(
                    store.hasWallpaper
                        ? AnyShapeStyle(theme.bg.opacity(store.backgroundOpacity))
                        : AnyShapeStyle(theme.bg)
                )

                // Full-height divider
                theme.border.frame(width: 1)

                // RIGHT COLUMN: tab bar + content + status line
                VStack(spacing: 0) {
                    // Tab bar (tabs only, no logo)
                    TabBarTabsArea()
                        .frame(height: Layout.tabBarHeight)

                    // Horizontal border under tabs
                    theme.border.frame(height: 1)

                    // Content area
                    ZStack {
                        if store.activeView == .settings {
                            if store.hasWallpaper {
                                theme.bg.opacity(store.backgroundOpacity)
                            } else {
                                theme.bg
                            }
                            SettingsPage(ghosttyApp: ghosttyApp)
                        } else if store.activeProjectId == nil {
                            if store.hasWallpaper {
                                theme.bg.opacity(store.backgroundOpacity)
                            } else {
                                theme.bg
                            }
                            StartScreen()
                        } else {
                            // Terminal — libghostty handles background transparency
                            // via background-opacity config. When no wallpaper is set,
                            // add a solid bg so the window isn't see-through.
                            if !store.hasWallpaper {
                                theme.bg
                            }
                            TerminalView(app: ghosttyApp)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Horizontal divider above status line
                    theme.border.frame(height: 1)

                    // Status line
                    StatusLine()
                        .frame(height: Layout.statusLineHeight)
                }
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
