import Foundation
import GhosttyKit

/// Wraps the ghostty_app_t lifecycle. One instance per app.
/// Blink controls all terminal settings — no Ghostty config files are loaded.
@MainActor
final class GhosttyApp {
    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?

    /// Weak refs for routing callbacks back to Swift objects.
    weak var store: AppStore?
    weak var surfaceManager: SurfaceManager?

    /// Whether ghostty_init has been called. Must happen exactly once.
    private static var initialized = false

    init() {
        // Initialize libghostty global state (thread pools, allocators, etc.)
        // Must happen exactly once before any other ghostty calls.
        if !Self.initialized {
            let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
            if result != GHOSTTY_SUCCESS {
                print("[GhosttyApp] ghostty_init failed with code \(result)")
                return
            }
            Self.initialized = true
        }

        // Create config — Blink owns all settings, no Ghostty config files loaded
        guard let cfg = ghostty_config_new() else {
            print("[GhosttyApp] Failed to create config")
            return
        }

        // Load persisted theme and wallpaper state for initial config
        let defaults = UserDefaults.standard
        let themeName = defaults.string(forKey: "blink.theme") ?? "Josean"
        let hasWallpaper = defaults.string(forKey: "blink.backgroundImage") != nil
        let opacity: Double
        if hasWallpaper, defaults.object(forKey: "blink.backgroundOpacity") != nil {
            opacity = defaults.double(forKey: "blink.backgroundOpacity")
        } else {
            opacity = 1.0
        }

        let configString: String
        if let defaultTheme = TerminalTheme.load(name: themeName) {
            configString = defaultTheme.toConfigString(backgroundOpacity: opacity)
        } else {
            configString = "background-opacity = \(opacity)\n"
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-ghostty-\(UUID().uuidString)")
            .appendingPathExtension("conf")

        do {
            try configString.write(to: tempURL, atomically: true, encoding: .utf8)
            ghostty_config_load_file(cfg, tempURL.path)
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            print("[GhosttyApp] Failed to write temp config: \(error)")
        }

        ghostty_config_finalize(cfg)
        self.config = cfg

        // Build runtime callbacks
        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = false

        // Wakeup callback — the sole driver of the render loop.
        // Called from any thread, must dispatch tick to main thread.
        runtime.wakeup_cb = { userdata in
            DispatchQueue.main.async {
                guard let ud = userdata else { return }
                let appWrapper = Unmanaged<GhosttyApp>.fromOpaque(ud).takeUnretainedValue()
                guard let ghosttyApp = appWrapper.app else { return }
                ghostty_app_tick(ghosttyApp)
            }
        }

        // Action callback — handle SET_TITLE for auto-updating tab names
        runtime.action_cb = { app, target, action in
            guard let app else { return false }
            guard let ud = ghostty_app_userdata(app) else { return false }
            let ghostty = Unmanaged<GhosttyApp>.fromOpaque(ud).takeUnretainedValue()

            switch action.tag {
            case GHOSTTY_ACTION_SET_TITLE:
                guard target.tag == GHOSTTY_TARGET_SURFACE else { return false }
                let surface = target.target.surface
                guard let titlePtr = action.action.set_title.title else { return false }
                let titleStr = String(cString: titlePtr)

                // Find the tab via the surface's view userdata
                if let viewPtr = ghostty_surface_userdata(surface) {
                    let view = Unmanaged<TerminalSurfaceView>.fromOpaque(viewPtr).takeUnretainedValue()
                    let tabId = view.tabId

                    DispatchQueue.main.async {
                        // Filter: only update title for known long-running processes
                        if let displayName = TabTitleFilter.displayName(for: titleStr) {
                            ghostty.store?.setTabTitle(tabId, title: displayName)
                        } else if TabTitleFilter.isShellPrompt(titleStr) {
                            // Back at shell prompt — revert to default tab name
                            ghostty.store?.revertTabTitle(tabId)
                        }
                        ghostty.store?.markUnread(tabId)
                    }
                }
                return true

            default:
                return false
            }
        }

        // Close surface callback — fired when shell process exits
        runtime.close_surface_cb = { userdata, _ in
            guard let ud = userdata else { return }
            let view = Unmanaged<TerminalSurfaceView>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async {
                view.onClose?(view.tabId)
            }
        }

        runtime.read_clipboard_cb = { _, _, _ in return false }
        runtime.confirm_read_clipboard_cb = { _, _, _, _ in }
        runtime.write_clipboard_cb = { _, _, _, _, _ in }

        // Create the app
        self.app = ghostty_app_new(&runtime, cfg)
        if self.app == nil {
            print("[GhosttyApp] Failed to create ghostty app")
        }
    }

    /// Hot-reload the terminal config with new theme colors and opacity.
    func updateConfig(terminalTheme: TerminalTheme, backgroundOpacity: Double) {
        guard let app else { return }

        let configString = terminalTheme.toConfigString(backgroundOpacity: backgroundOpacity)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-ghostty-\(UUID().uuidString)")
            .appendingPathExtension("conf")

        guard let _ = try? configString.write(to: tempURL, atomically: true, encoding: .utf8) else {
            print("[GhosttyApp] Failed to write temp config for update")
            return
        }

        guard let newCfg = ghostty_config_new() else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        ghostty_config_load_file(newCfg, tempURL.path)
        try? FileManager.default.removeItem(at: tempURL)
        ghostty_config_finalize(newCfg)

        ghostty_app_update_config(app, newCfg)

        // We own the config lifecycle — free old, keep new
        if let oldConfig = config {
            ghostty_config_free(oldConfig)
        }
        config = newCfg
    }

    deinit {
        if let app { ghostty_app_free(app) }
        if let config { ghostty_config_free(config) }
    }
}
