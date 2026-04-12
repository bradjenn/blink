import AppKit
import SwiftUI
import GhosttyKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let closeShortcutNotification = Notification.Name("BlinkCloseActiveTabShortcut")
    private let popupWindowIdentifier = NSUserInterfaceItemIdentifier("BlinkChromiumPopupWindow")

    private var menuObserver: Any?
    private var closeShortcutObserver: Any?
    private var closeShortcutMonitor: Any?
    private var closeTabTerminationGuardUntil: Date?

    var closeActiveTab: () -> Void = {}
    var canCloseActiveTab: () -> Bool = { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.configureKeyboardShortcuts()
        }

        // SwiftUI rebuilds menus on state changes, re-adding system shortcuts.
        // Observe menu updates to re-apply Blink's command routing.
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didAddItemNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.configureKeyboardShortcuts()
        }

        closeShortcutObserver = NotificationCenter.default.addObserver(
            forName: closeShortcutNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.requestCloseActiveTab()
        }

        closeShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let characters = event.charactersIgnoringModifiers?.lowercased()
            guard modifiers == [.command],
                  characters == "w",
                  self?.shouldHandleCloseShortcut(for: NSApp.keyWindow) == true else {
                return event
            }

            self?.requestCloseActiveTab()
            return nil
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        configureKeyboardShortcuts()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: BrowserManager.willTerminateNotification, object: nil)
        BlinkChromiumRuntime.shared().shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func requestCloseActiveTab() {
        closeTabTerminationGuardUntil = Date().addingTimeInterval(1)
        closeActiveTab()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let deadline = closeTabTerminationGuardUntil,
           deadline > Date() {
            closeTabTerminationGuardUntil = nil
            return .terminateCancel
        }

        return .terminateNow
    }

    @objc func handleCloseMenuCommand(_ sender: Any?) {
        guard shouldHandleCloseShortcut(for: NSApp.keyWindow) else {
            NSApp.keyWindow?.performClose(sender)
            return
        }

        requestCloseActiveTab()
    }

    private func configureKeyboardShortcuts() {
        guard let mainMenu = NSApp.mainMenu else { return }

        clearKeyEquivalent(
            in: mainMenu,
            action: #selector(NSApplication.hide(_:)),
            key: "h",
            modifiers: [.command]
        )

        configureCloseCommand(in: mainMenu)
    }

    private func configureCloseCommand(in menu: NSMenu) {
        for item in menu.items {
            if item.keyEquivalent.lowercased() == "w",
               item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == [.command] {
                item.action = #selector(handleCloseMenuCommand(_:))
                item.target = self
            }

            if let submenu = item.submenu {
                configureCloseCommand(in: submenu)
            }
        }
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

    private func shouldHandleCloseShortcut(for window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window.identifier != popupWindowIdentifier
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(handleCloseMenuCommand(_:)) else { return true }

        let shouldHandleShortcut = shouldHandleCloseShortcut(for: NSApp.keyWindow)
        menuItem.title = shouldHandleShortcut ? "Close Tab" : "Close"
        return shouldHandleShortcut ? canCloseActiveTab() : NSApp.keyWindow != nil
    }
}

struct BApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var themeManager = ThemeManager()
    @State private var store = AppStore()
    @State private var ghosttyApp = GhosttyApp()
    @State private var surfaceManager = SurfaceManager()
    @State private var browserManager = BrowserManager()
    @State private var gitMonitor = GitStatusMonitor()
    @State private var spotifyMonitor = SpotifyMonitor()
    @State private var updateChecker = UpdateChecker()

    var body: some Scene {
        WindowGroup(id: "main") {
            Shell(
                ghosttyApp: ghosttyApp,
                surfaceManager: surfaceManager,
                browserManager: browserManager
            )
                .background(
                    WindowTitleBarConfigurator()
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
                .alert(
                    updateChecker.presentedAlert?.title ?? "",
                    isPresented: Binding(
                        get: { updateChecker.presentedAlert != nil },
                        set: { isPresented in
                            if !isPresented {
                                updateChecker.dismissAlert()
                            }
                        }
                    )
                ) {
                    if case .updateAvailable(let release) = updateChecker.presentedAlert {
                        Button("View Release") {
                            updateChecker.openReleasePage(for: release)
                            updateChecker.dismissAlert()
                        }
                    }

                    Button("OK", role: .cancel) {
                        updateChecker.dismissAlert()
                    }
                } message: {
                    Text(updateChecker.presentedAlert?.message ?? "")
                }
                .onAppear {
                    appDelegate.closeActiveTab = {
                        guard store.activeWorkspaceId != nil,
                              !store.showWorkspaceSwitcher,
                              !store.showWorkspaceOnboarding,
                              !store.showThemePicker,
                              !store.showAISessionPicker,
                              !store.showCommandPalette,
                              store.workspacePrompt == nil,
                              store.activeView == .workspaces else { return }
                        store.closeActiveTab()
                    }
                    appDelegate.canCloseActiveTab = {
                        store.activeWorkspaceId != nil &&
                        !store.showAISessionPicker &&
                        !store.showWorkspaceOnboarding &&
                        !store.showWorkspaceSwitcher &&
                        !store.showThemePicker &&
                        !store.showCommandPalette &&
                        store.workspacePrompt == nil &&
                        store.activeView == .workspaces
                    }

                    updateChecker.checkIfNeeded()
                    if store.spotifyEnabled {
                        spotifyMonitor.startMonitoring(performInitialRefresh: false)
                    }
                    // Wire GhosttyApp to store and surface manager for callbacks
                    ghosttyApp.store = store
                    ghosttyApp.surfaceManager = surfaceManager
                    store.surfaceManager = surfaceManager
                    store.browserManager = browserManager
                    surfaceManager.onProcessExit = { tabId in
                        if store.handleProcessExit(for: tabId) {
                            surfaceManager.destroySurface(tabId: tabId)
                        }
                    }
                    surfaceManager.onSurfaceReady = { tabId in
                        store.handleTerminalSurfaceReady(for: tabId)
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
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Check for Updates...") {
                    Task { await updateChecker.check() }
                }
                .disabled(updateChecker.isChecking)

                Button("Settings...") {
                    store.toggleSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .printItem) {
                Button("Command Palette...") {
                    store.presentCommandPalette()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                Button("Open Scratch Space") {
                    store.openScratchSpace()
                }

                Button("New Workspace...") {
                    store.presentWorkspaceOnboarding()
                }

                Button("Switch Workspace...") {
                    store.presentWorkspaceSwitcher()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(store.workspaces.isEmpty)

                Button("Switch Theme...") {
                    store.presentThemePicker()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(themeManager.availableThemes.isEmpty)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Toggle Workspace Browser Sidebar") {
                    store.toggleActiveBrowserSidebarPinned()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(store.tabsById[store.activeTabId ?? ""]?.isBrowser != true)
            }

            CommandGroup(after: .toolbar) {
                Button(store.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    if store.sidebarVisible {
                        store.toggleSidebar()
                    } else {
                        store.focusSidebar()
                    }
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Focus Sidebar") {
                    store.focusSidebar()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Focus Left") {
                    store.focusLeft()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Button("Focus Right") {
                    store.focusRight()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

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

                Button("Open AI Session...") {
                    store.presentAISessionPicker()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("Open Git") {
                    store.openOrFocusCommandTabForActiveWorkspace(command: "lazygit", label: "lazygit")
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Open Files") {
                    let command = YaziLauncher.command(theme: themeManager.activeTerminalTheme)
                    store.openOrFocusCommandTabForActiveWorkspace(command: command, label: "Yazi")
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Open Neovim") {
                    let command = NvimLauncher.command(theme: themeManager.activeTerminalTheme)
                    store.openOrFocusCommandTabForActiveWorkspace(command: command, label: "Neovim")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Open Spotify") {
                    let command = themeManager.activeTerminalTheme?.spotatuiLaunchCommand() ?? "spotatui"
                    store.openOrFocusCommandTabForActiveWorkspace(command: command, label: "Spotify", maximizeColumn: true)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Open Workspace Browser") {
                    store.openBrowserTabForActiveWorkspace()
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(store.activeWorkspaceId == nil)

                Button("Focus Workspace Browser Address Bar") {
                    store.focusBrowserAddressBar()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(!store.hasActiveBrowserSelection || store.hasBlockingModalPresentation)

                Button("Focus Workspace Browser Content") {
                    store.focusBrowserWebView()
                }
                .disabled(!store.hasActiveBrowserSelection)

                Button("Workspace Browser Back") {
                    store.navigateActiveBrowserBack()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!store.hasActiveBrowserSelection)

                Button("Workspace Browser Forward") {
                    store.navigateActiveBrowserForward()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!store.hasActiveBrowserSelection)

                Button("Workspace Browser Reload") {
                    store.reloadActiveBrowser()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!store.hasActiveBrowserSelection)

                Button("Toggle Workspace Browser Developer Tools") {
                    store.toggleActiveBrowserDeveloperTools()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(!store.hasActiveBrowserSelection)

                Button("Open Page in Default Browser") {
                    store.openActiveBrowserInDefaultBrowser()
                }
                .disabled(!store.hasActiveBrowserSelection)
            }

            CommandGroup(replacing: .newItem) {
                Button("Open Scratch Space") {
                    store.openScratchSpace()
                }

                Divider()

                Button("New Tab") {
                    store.openNewTabForActiveSurface()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(store.activeWorkspaceId == nil)

                Button("New Workspace Browser") {
                    store.openBrowserTabForActiveWorkspace()
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(store.activeWorkspaceId == nil)

                Button("Split Below") {
                    store.splitActivePaneWithNewTab()
                }
                .keyboardShortcut("-", modifiers: [.command, .shift])
                .disabled(store.activeWorkspaceId == nil)

                Button("Split Right") {
                    store.splitActiveColumnWithNewTab()
                }
                .keyboardShortcut("\\", modifiers: [.command, .shift])
                .disabled(store.activeWorkspaceId == nil)

                Divider()

                ForEach(1...9, id: \.self) { number in
                    Button("Window \(number)") {
                        if let workspaceId = store.activeWorkspaceId {
                            let ordered = store.orderedTabs(for: workspaceId)
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
