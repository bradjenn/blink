import SwiftUI
import GhosttyKit

struct Shell: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager

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
                    TabBarLogoArea()
                        .frame(height: Layout.tabBarHeight)

                    theme.border.frame(height: 1)

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
                    TabBarTabsArea(
                        ghosttyApp: ghosttyApp,
                        surfaceManager: surfaceManager
                    )
                    .frame(height: Layout.tabBarHeight)

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
                        } else if let tabId = store.activeTabId,
                                  let projectId = store.activeProjectId,
                                  let project = store.projects.first(where: { $0.id == projectId }) {
                            if !store.hasWallpaper {
                                theme.bg
                            }
                            TerminalView(
                                tabId: tabId,
                                ghosttyApp: ghosttyApp,
                                surfaceManager: surfaceManager,
                                workingDirectory: project.path
                            )
                        } else {
                            // Project selected but no tabs yet
                            if store.hasWallpaper {
                                theme.bg.opacity(store.backgroundOpacity)
                            } else {
                                theme.bg
                            }
                            VStack(spacing: 12) {
                                Text("No terminals open")
                                    .font(Fonts.primary(size: 16))
                                    .foregroundStyle(theme.textDim)
                                Text("Press + to open a terminal")
                                    .font(Fonts.primary(size: 13))
                                    .foregroundStyle(theme.textDim)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    theme.border.frame(height: 1)

                    StatusLine()
                        .frame(height: Layout.statusLineHeight)
                }
            }
            .background(store.hasWallpaper ? Color.clear : theme.bg)
            .font(Fonts.primary(size: 13))
        }
    }

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
