import SwiftUI
import GhosttyKit

struct Shell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager

    @State private var isSettingsHovered = false

    private var topBarLeadingWidth: CGFloat {
        store.sidebarVisible ? Layout.sidebarWidth : Layout.logoAreaCollapsedWidth
    }

    private var footerLeadingWidth: CGFloat {
        store.sidebarVisible ? Layout.sidebarWidth : Layout.sidebarCollapsedWidth
    }

    private var isSettingsActive: Bool {
        store.activeView == .settings
    }

    private var chromeBackground: AnyShapeStyle {
        store.hasWallpaper
            ? AnyShapeStyle(theme.bg.opacity(store.backgroundOpacity))
            : AnyShapeStyle(theme.bg)
    }

    private var settingsPageTransition: AnyTransition {
        .opacity
    }

    private var topBarContentTransition: AnyTransition {
        .opacity
    }

    @ViewBuilder
    private var windowBackground: some View {
        Rectangle()
            .fill(chromeBackground)

        if let wallpaperId = store.backgroundImage {
            wallpaperImage(for: wallpaperId)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.1)
                .blur(radius: store.backgroundBlur)
                .clipped()
        }
    }

    var body: some View {
        ZStack {
            // Layout — each panel owns its background surface
            VStack(spacing: 0) {

                // ── TOP BAR ──────────────────────────────────────
                HStack(spacing: 0) {
                    TabBarLogoArea()
                        .frame(width: topBarLeadingWidth, alignment: .leading)
                        .frame(height: Layout.tabBarHeight)

                    theme.border.frame(width: 1, height: Layout.tabBarHeight)

                    ZStack {
                        if !isSettingsActive {
                            TabBarTabsArea(
                                ghosttyApp: ghosttyApp,
                                surfaceManager: surfaceManager
                            )
                            .transition(topBarContentTransition)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.tabBarHeight)
                }
                .background(chromeBackground)
                .background(WindowDragRegion())
                .animation(.snappy(duration: 0.25), value: store.sidebarVisible)
                .animation(.snappy(duration: 0.25), value: isSettingsActive)

                theme.border.frame(height: 1)

                // ── MIDDLE ───────────────────────────────────────
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(chromeBackground)

                    Group {
                        if store.activeProjectId == nil {
                            StartScreen()
                        } else if let tabId = store.activeTabId,
                                  let projectId = store.activeProjectId,
                                  let project = store.projects.first(where: { $0.id == projectId }) {
                            TerminalView(
                                tabId: tabId,
                                ghosttyApp: ghosttyApp,
                                surfaceManager: surfaceManager,
                                workingDirectory: project.path,
                                command: store.tabs.first(where: { $0.id == tabId })?.command
                            )
                        } else {
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
                    .padding(.leading, store.sidebarVisible ? Layout.sidebarWidth + 1 : 0)
                    .animation(.snappy(duration: 0.25), value: store.sidebarVisible)

                    HStack(spacing: 0) {
                        SidebarView()
                            .frame(width: Layout.sidebarWidth)
                            .frame(maxHeight: .infinity)

                        theme.border.frame(width: 1)
                    }
                    .offset(x: store.sidebarVisible ? 0 : -(Layout.sidebarWidth + 1))
                    .allowsHitTesting(store.sidebarVisible)
                    .accessibilityHidden(!store.sidebarVisible)
                    .animation(.snappy(duration: 0.25), value: store.sidebarVisible)
                }
                .clipped()
                .animation(.snappy(duration: 0.25), value: isSettingsActive)

                theme.border.frame(height: 1)

                // ── FOOTER ───────────────────────────────────────
                HStack(spacing: 0) {
                    Button(action: { store.setActiveView(.settings) }) {
                        HStack(spacing: store.sidebarVisible ? 10 : 0) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14, weight: .light))
                            if store.sidebarVisible {
                                Text("Settings")
                                    .font(Fonts.primary(size: 12.5).leading(.tight))
                            }
                        }
                        .foregroundStyle((isSettingsHovered || isSettingsActive) ? theme.text : theme.textDim)
                        .frame(maxWidth: .infinity, alignment: store.sidebarVisible ? .leading : .center)
                        .frame(height: Layout.statusLineHeight)
                        .padding(.horizontal, store.sidebarVisible ? 16 : 0)
                        .background(
                            (isSettingsHovered || isSettingsActive)
                                ? theme.accent.opacity(0.05)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isSettingsHovered = $0 }
                    .pointerCursor()
                    .frame(width: footerLeadingWidth)

                    theme.border.frame(width: 1, height: Layout.statusLineHeight)

                    StatusLine()
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.statusLineHeight)
                }
                .background(chromeBackground)
                .animation(.snappy(duration: 0.25), value: store.sidebarVisible)
            }
            .font(Fonts.primary(size: 13))
            .ignoresSafeArea(.container, edges: .top)

            // Settings — full window overlay covering header, content, and footer
            if isSettingsActive {
                SettingsPage(ghosttyApp: ghosttyApp)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Rectangle().fill(chromeBackground))
                    .transition(settingsPageTransition)
                    .zIndex(1)
            }

            // Theme picker — top level so backdrop covers entire window
            if store.showProjectSwitcher {
                StartScreenProjectPicker(
                    onDismiss: { store.dismissProjectSwitcher() },
                    onSelect: { projectId in
                        store.openProjectSession(projectId)
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }

            if store.showThemePicker {
                ThemePicker(
                    ghosttyApp: ghosttyApp,
                    onDismiss: { store.dismissThemePicker() }
                )
                .zIndex(2)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            windowBackground
                .ignoresSafeArea()
        }
    }

    private func wallpaperImage(for id: String) -> Image {
        if let preset = WallpaperPreset.find(id) {
            let parts = preset.filename.split(separator: ".")
            if parts.count == 2,
               let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1])),
               let nsImage = NSImage(contentsOf: url) {
                return Image(nsImage: nsImage)
            }
        } else if !id.hasPrefix("preset:"), let nsImage = NSImage(contentsOfFile: id) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "photo")
    }
}
