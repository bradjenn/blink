import SwiftUI
import GhosttyKit

class AppDelegate: NSObject, NSApplicationDelegate {}

@main
struct BApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var themeManager = ThemeManager()
    @State private var store = AppStore()
    @State private var ghosttyApp = GhosttyApp()
    @State private var surfaceManager = SurfaceManager()
    @State private var gitMonitor = GitStatusMonitor()

    var body: some Scene {
        WindowGroup {
            Shell(ghosttyApp: ghosttyApp, surfaceManager: surfaceManager)
                .background(WindowTitleBarConfigurator())
                .environment(store)
                .environment(themeManager)
                .environment(gitMonitor)
                .environment(\.theme, themeManager.activeTheme)
                .frame(
                    minWidth: Layout.windowMinWidth,
                    minHeight: Layout.windowMinHeight
                )
                .preferredColorScheme(.dark)
                .onAppear {
                    // Wire GhosttyApp to store and surface manager for callbacks
                    ghosttyApp.store = store
                    ghosttyApp.surfaceManager = surfaceManager
                    store.surfaceManager = surfaceManager
                    surfaceManager.onProcessExit = { tabId in
                        // Auto-close tabs that ran a command (e.g. lazygit)
                        if let tab = store.tabs.first(where: { $0.id == tabId }), tab.command != nil {
                            surfaceManager.destroySurface(tabId: tabId)
                            store.closeTab(tabId)
                        }
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
                Button("Settings...") {
                    store.setActiveView(.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .printItem) {
                Button("Switch Project...") {
                    store.presentProjectSwitcher()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(store.projects.isEmpty)
            }

            CommandGroup(after: .toolbar) {
                Button(store.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    store.toggleSidebar()
                }
                .keyboardShortcut("b", modifiers: .command)

                Button(store.sidebarFocused ? "Focus Terminal" : "Focus Sidebar") {
                    store.toggleSidebarFocus()
                }
                .keyboardShortcut("h", modifiers: .control)

                Button("Focus Terminal") {
                    store.focusTerminal()
                }
                .keyboardShortcut("l", modifiers: .control)

                Button("Open Git") {
                    if let projectId = store.activeProjectId {
                        if let existing = store.projectTabs(for: projectId).first(where: { $0.command == "lazygit" }) {
                            store.setActiveTab(existing.id)
                        } else {
                            store.openTab(projectId: projectId, command: "lazygit", label: "lazygit")
                        }
                    }
                }
                .keyboardShortcut("g", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    if let projectId = store.activeProjectId {
                        store.openTab(projectId: projectId)
                    }
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    if let tabId = store.activeTabId {
                        store.closeTab(tabId)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                ForEach(1...9, id: \.self) { number in
                    Button("Tab \(number)") {
                        if let projectId = store.activeProjectId {
                            let projectTabs = store.projectTabs(for: projectId)
                            if number <= projectTabs.count {
                                store.setActiveTab(projectTabs[number - 1].id)
                            }
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                }
            }
        }
    }
}
