import SwiftUI
import GhosttyKit

struct Shell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager
    let browserManager: BrowserManager

    @State private var escapeMonitor: Any?
    @State private var shortcutMonitor: Any?

    private var isSettingsActive: Bool {
        store.activeView == .settings
    }

    private var chromeBackground: AnyShapeStyle {
        store.hasWallpaper
            ? AnyShapeStyle(theme.bg.opacity(store.backgroundOpacity))
            : AnyShapeStyle(theme.bg)
    }

    private var settingsBackground: AnyShapeStyle {
        if store.hasWallpaper {
            let opacity = max(store.backgroundOpacity + 0.22, 0.9)
            return AnyShapeStyle(theme.bg.opacity(min(opacity, 0.97)))
        } else {
            return AnyShapeStyle(theme.bg.opacity(0.97))
        }
    }

    private var sidebarAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .snappy(duration: 0.18, extraBounce: 0)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                workspaceArea

                if activeWorkspace != nil {
                    theme.border.frame(height: 1)
                    footer
                }
            }
            .font(Fonts.primary(size: 13))

            SettingsPage(ghosttyApp: ghosttyApp)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.85), lineWidth: 1)
                )
                .padding(.horizontal, Layout.workspacePaddingH)
                .padding(.top, Layout.workspacePaddingV)
                .padding(.bottom, 8)
                .background(Rectangle().fill(settingsBackground))
                .opacity(isSettingsActive ? 1 : 0)
                .scaleEffect(isSettingsActive ? 1 : 0.97)
                .animation(.easeOut(duration: 0.25), value: isSettingsActive)
                .allowsHitTesting(isSettingsActive)
                .zIndex(1)

            if store.showWorkspaceSwitcher {
                StartScreenWorkspacePicker(
                    onDismiss: { store.dismissWorkspaceSwitcher() },
                    onSelect: { workspaceId in
                        store.openWorkspaceSession(workspaceId)
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }

            if store.showWorkspaceOnboarding {
                WorkspaceOnboarding(
                    onDismiss: { store.dismissWorkspaceOnboarding() }
                )
                .zIndex(2)
            }

            if store.showThemePicker {
                ThemePicker(
                    ghosttyApp: ghosttyApp,
                    onDismiss: { store.showThemePicker = false }
                )
                .zIndex(3)
            }

            if store.showAISessionPicker {
                AISessionPicker(
                    onDismiss: { store.dismissAISessionPicker() }
                )
                .zIndex(4)
            }

            if store.showCommandPalette {
                CommandPalette(
                    onDismiss: { store.dismissCommandPalette() }
                )
                .zIndex(5)
            }

            if let prompt = store.workspacePrompt {
                WorkspacePromptModal(
                    prompt: prompt,
                    onDismiss: { store.dismissWorkspacePrompt() }
                )
                .zIndex(6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            windowBackground
                .ignoresSafeArea()
        }
        .onAppear {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [store] event in
                guard event.keyCode == 53, // Escape
                      store.activeView == .settings else { return event }
                DispatchQueue.main.async { store.toggleSettings() }
                return nil
            }
            shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [store] event in
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard store.activeWorkspaceId != nil,
                      !store.showWorkspaceSwitcher,
                      !store.showWorkspaceOnboarding,
                      !store.showThemePicker,
                      !store.showAISessionPicker,
                      !store.showCommandPalette,
                      store.workspacePrompt == nil,
                      store.activeView == .workspaces else { return event }

                switch modifiers {
                case [.command]:
                    switch event.keyCode {
                    case 123: // Left arrow
                        DispatchQueue.main.async {
                            store.focusLeft()
                        }
                        return nil
                    case 124: // Right arrow
                        DispatchQueue.main.async {
                            store.focusRight()
                        }
                        return nil
                    default:
                        switch event.charactersIgnoringModifiers?.lowercased() {
                        case "h":
                            DispatchQueue.main.async {
                                store.focusLeft()
                            }
                            return nil
                        case "l":
                            DispatchQueue.main.async {
                                store.focusRight()
                            }
                            return nil
                        default:
                            return event
                        }
                    }
                case [.command, .shift]:
                    switch event.charactersIgnoringModifiers {
                    case "-":
                        DispatchQueue.main.async {
                            store.splitActivePaneWithNewTab()
                        }
                        return nil
                    case "\\":
                        DispatchQueue.main.async {
                            store.splitActiveColumnWithNewTab()
                        }
                        return nil
                    default:
                        return event
                    }
                default:
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = escapeMonitor {
                NSEvent.removeMonitor(monitor)
                escapeMonitor = nil
            }
            if let monitor = shortcutMonitor {
                NSEvent.removeMonitor(monitor)
                shortcutMonitor = nil
            }
        }
    }

    private var workspaceArea: some View {
        ZStack {
            if store.activeWorkspaceId != nil {
                Rectangle()
                    .fill(chromeBackground)
            }

            if store.activeWorkspaceId == nil {
                Rectangle()
                    .fill(chromeBackground)
                    .overlay {
                        StartScreen()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
            } else if let workspace = activeWorkspace {
                HStack(alignment: .top, spacing: Layout.workspaceColumnSpacing) {
                    if store.sidebarVisible {
                        WorkspaceSidebarPanel()
                            .frame(width: Layout.sidebarWidth)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    WorkspaceColumnsView(
                        workspace: workspace,
                        ghosttyApp: ghosttyApp,
                        surfaceManager: surfaceManager,
                        browserManager: browserManager
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, Layout.workspacePaddingH)
                .padding(.top, Layout.workspacePaddingV)
                .padding(.bottom, 8)
                .animation(sidebarAnimation, value: store.sidebarVisible)
            } else {
                VStack(spacing: 12) {
                    Text("No workspace available")
                        .font(Fonts.primary(size: 16))
                        .foregroundStyle(theme.textDim)
                    Text("Select a workspace to open a workspace")
                        .font(Fonts.primary(size: 13))
                        .foregroundStyle(theme.textDim)
                }
            }
        }
        .clipped()
    }

    private var footer: some View {
        FooterBar(
            onToggleSidebar: toggleSidebar,
            onShowSettings: showSettings
        )
        .frame(height: Layout.statusLineHeight)
        .background(chromeBackground)
        .background(WindowDragRegion())
    }

    @ViewBuilder
    private var windowBackground: some View {
        Rectangle()
            .fill(chromeBackground)

        if store.backgroundImage != nil {
            if let cached = store.cachedBlurredWallpaper {
                Image(nsImage: cached)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(1.1)
                    .clipped()
            }
        }
    }

    private var activeWorkspace: Workspace? {
        guard let activeWorkspaceId = store.activeWorkspaceId else { return nil }
        return store.workspaces.first(where: { $0.id == activeWorkspaceId })
    }

    private func showSettings() {
        store.toggleSettings()
    }

    private func toggleSidebar() {
        store.toggleSidebar()
    }

}
