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
        }
    }
}
