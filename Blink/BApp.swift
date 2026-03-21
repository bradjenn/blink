import SwiftUI
import GhosttyKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.clearReservedKeyboardShortcuts()
        }
        // SwiftUI rebuilds menus on state changes, re-adding system shortcuts.
        // Observe menu updates to re-clear them.
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didAddItemNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearReservedKeyboardShortcuts()
        }

    }

    func applicationDidBecomeActive(_ notification: Notification) {
        clearReservedKeyboardShortcuts()
    }


    private func clearReservedKeyboardShortcuts() {
        guard let mainMenu = NSApp.mainMenu else { return }

        clearKeyEquivalent(
            in: mainMenu,
            action: #selector(NSApplication.hide(_:)),
            key: "h",
            modifiers: [.command]
        )
    }

    private func clearKeyEquivalent(
        in menu: NSMenu,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags
    ) {
        for item in menu.items {
            if item.action == action,
               item.keyEquivalent.lowercased() == key,
               item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == modifiers {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
            }

            if let submenu = item.submenu {
                clearKeyEquivalent(in: submenu, action: action, key: key, modifiers: modifiers)
            }
        }
    }
}

@main
struct BApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var themeManager = ThemeManager()
    @State private var store = AppStore()
    @State private var ghosttyApp = GhosttyApp()
    @State private var surfaceManager = SurfaceManager()
    @State private var gitMonitor = GitStatusMonitor()
    @State private var spotifyMonitor = SpotifyMonitor()
    @State private var updateChecker = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            Shell(ghosttyApp: ghosttyApp, surfaceManager: surfaceManager)
                .background(
                    WindowTitleBarConfigurator(
                        onCloseRequest: { store.closeActiveTab() }
                    )
                )
                .environment(store)
                .environment(themeManager)
                .environment(gitMonitor)
                .environment(spotifyMonitor)
                .environment(updateChecker)
                .environment(\.theme, themeManager.activeTheme)
                .frame(
                    minWidth: Layout.windowMinWidth,
                    minHeight: Layout.windowMinHeight
                )
                .preferredColorScheme(.dark)
                .onAppear {
                    updateChecker.checkIfNeeded()
                    if store.spotifyEnabled {
                        spotifyMonitor.startMonitoring()
                    }
                    // Wire GhosttyApp to store and surface manager for callbacks
                    ghosttyApp.store = store
                    ghosttyApp.surfaceManager = surfaceManager
                    store.surfaceManager = surfaceManager
                    surfaceManager.onProcessExit = { tabId in
                        // Auto-close tabs that ran a command (e.g. lazygit)
                        if let tab = store.tabsById[tabId], tab.command != nil {
                            store.closeTab(tabId)
                        }
                    }
                }
                .onChange(of: store.spotifyEnabled) {
                    if store.spotifyEnabled {
                        spotifyMonitor.startMonitoring()
                    } else {
                        spotifyMonitor.stopMonitoring()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: Layout.windowDefaultWidth,
            height: Layout.windowDefaultHeight
        )
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Check for Updates...") {
                    Task { await updateChecker.check() }
                }

                Button("Settings...") {
                    store.toggleSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .printItem) {
                Button("Switch Project...") {
                    store.presentProjectSwitcher()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(store.projects.isEmpty)

                Button("Switch Theme...") {
                    store.presentThemePicker()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(themeManager.availableThemes.isEmpty)
            }

            CommandGroup(after: .toolbar) {
                Button(store.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    store.toggleSidebar()
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Focus Left") {
                    store.focusLeft()
                }
                .keyboardShortcut("h", modifiers: .command)

                Button("Focus Right") {
                    store.focusRight()
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Focus Down") {
                    store.focusDown()
                }
                .keyboardShortcut("j", modifiers: .command)

                Button("Focus Up") {
                    store.focusUp()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Move Window Left") {
                    store.moveColumnLeft()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("Move Window Right") {
                    store.moveColumnRight()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Absorb from Left") {
                    store.absorbFromLeft()
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])

                Button("Absorb from Right") {
                    store.absorbFromRight()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Expel Pane") {
                    store.expelActiveTab()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Overview") {
                    store.toggleOverview()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Open Git") {
                    store.openOrFocusCommandTabForActiveProject(command: "lazygit", label: "lazygit")
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Open Files") {
                    store.openOrFocusCommandTabForActiveProject(command: "yazi", label: "Yazi", fullWidth: true)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    if let projectId = store.activeProjectId {
                        store.openTab(projectId: projectId)
                    }
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Window") {
                    store.closeActiveTab()
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                ForEach(1...9, id: \.self) { number in
                    Button("Window \(number)") {
                        if let projectId = store.activeProjectId {
                            let ordered = store.orderedTabs(for: projectId)
                            if number <= ordered.count {
                                store.setActiveTab(ordered[number - 1].id)
                            }
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                }
            }
        }
    }
}
