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

    var body: some Scene {
        WindowGroup {
            Shell(ghosttyApp: ghosttyApp, surfaceManager: surfaceManager)
                .background(WindowTitleBarConfigurator())
                .environment(store)
                .environment(themeManager)
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
