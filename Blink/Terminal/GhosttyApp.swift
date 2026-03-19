import Foundation
import AppKit
import GhosttyKit
import UniformTypeIdentifiers

private extension NSPasteboard.PasteboardType {
    init?(ghosttyMIMEType mimeType: String) {
        switch mimeType {
        case "text/plain":
            self = .string
        default:
            if let utType = UTType(mimeType: mimeType) {
                self.init(utType.identifier)
            } else {
                self.init(mimeType)
            }
        }
    }
}

private extension NSPasteboard {
    static let blinkSelection = NSPasteboard(name: .init("com.blink.app.selection"))

    static func blink(_ clipboard: ghostty_clipboard_e) -> NSPasteboard? {
        switch clipboard {
        case GHOSTTY_CLIPBOARD_STANDARD:
            return .general
        case GHOSTTY_CLIPBOARD_SELECTION:
            return .blinkSelection
        default:
            return nil
        }
    }

    func blinkStringContents() -> String? {
        string(forType: .string)
    }
}

/// Wraps the ghostty_app_t lifecycle. One instance per app.
/// Blink controls all terminal settings — no Ghostty config files are loaded.
@MainActor
final class GhosttyApp {
    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?
    private var configTemplateCache: [String: ghostty_config_t] = [:]
    private var activeConfigKey: String?

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

        let fontFamily = defaults.string(forKey: "blink.fontFamily") ?? "MesloLGS Nerd Font Mono"
        let fontSize = defaults.object(forKey: "blink.fontSize") != nil
            ? defaults.double(forKey: "blink.fontSize") : 19.0
        let cursorStyle = CursorStyle(rawValue: defaults.string(forKey: "blink.cursorStyle") ?? "") ?? .block

        let configString: String
        if let defaultTheme = TerminalTheme.load(name: themeName) {
            configString = defaultTheme.toConfigString(
                backgroundOpacity: opacity,
                fontFamily: fontFamily,
                fontSize: fontSize,
                cursorStyle: cursorStyle
            )
        } else {
            configString = "background-opacity = \(opacity)\n"
        }
        guard let cfg = clonedConfig(for: configString) ?? buildConfig(from: configString) else {
            print("[GhosttyApp] Failed to create config")
            return
        }
        self.config = cfg
        self.activeConfigKey = configString

        // Build runtime callbacks
        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = true

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
                        // Skip title updates for tabs with an explicit command (e.g. lazygit)
                        let isCommandTab = ghostty.store?.tabs.first(where: { $0.id == tabId })?.command != nil
                        if !isCommandTab {
                            // Filter: only update title for known long-running processes
                            if let displayName = TabTitleFilter.displayName(for: titleStr) {
                                ghostty.store?.setTabTitle(tabId, title: displayName)
                            } else if TabTitleFilter.isShellPrompt(titleStr) {
                                // Back at shell prompt — revert to default tab name
                                ghostty.store?.revertTabTitle(tabId)
                            }
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

        runtime.read_clipboard_cb = { userdata, clipboard, state in
            guard let userdata, let state else { return false }
            let view = Unmanaged<TerminalSurfaceView>.fromOpaque(userdata).takeUnretainedValue()
            guard let pasteboard = NSPasteboard.blink(clipboard),
                  let value = pasteboard.blinkStringContents() else {
                return false
            }

            view.completeClipboardRequest(value, state: state)
            return true
        }
        runtime.confirm_read_clipboard_cb = { userdata, string, state, _ in
            guard let userdata, let string, let state else { return }
            let view = Unmanaged<TerminalSurfaceView>.fromOpaque(userdata).takeUnretainedValue()
            view.completeClipboardRequest(String(cString: string), state: state, confirmed: true)
        }
        runtime.write_clipboard_cb = { _, clipboard, content, len, _ in
            guard let pasteboard = NSPasteboard.blink(clipboard),
                  let content,
                  len > 0 else {
                return
            }

            let items = (0..<len).compactMap { index -> (type: NSPasteboard.PasteboardType, value: String)? in
                let entry = content[index]
                guard let mime = String(validatingUTF8: entry.mime),
                      let value = String(validatingUTF8: entry.data),
                      let type = NSPasteboard.PasteboardType(ghosttyMIMEType: mime) else {
                    return nil
                }
                return (type, value)
            }
            guard !items.isEmpty else { return }

            pasteboard.declareTypes(items.map(\.type), owner: nil)
            for item in items {
                pasteboard.setString(item.value, forType: item.type)
            }
        }

        // Create the app
        self.app = ghostty_app_new(&runtime, cfg)
        if self.app == nil {
            print("[GhosttyApp] Failed to create ghostty app")
        }
    }

    /// Hot-reload the terminal config with new theme colors and opacity.
    func updateConfig(
        terminalTheme: TerminalTheme,
        backgroundOpacity: Double,
        fontFamily: String = "MesloLGS Nerd Font Mono",
        fontSize: Double = 19,
        cursorStyle: CursorStyle = .block
    ) {
        guard let app else { return }

        let configString = terminalTheme.toConfigString(
            backgroundOpacity: backgroundOpacity,
            fontFamily: fontFamily,
            fontSize: fontSize,
            cursorStyle: cursorStyle
        )
        guard activeConfigKey != configString else { return }

        guard let newCfg = clonedConfig(for: configString) ?? buildConfig(from: configString) else {
            return
        }

        ghostty_app_update_config(app, newCfg)

        // We own the config lifecycle — free old, keep new
        if let oldConfig = config {
            ghostty_config_free(oldConfig)
        }
        config = newCfg
        activeConfigKey = configString
    }

    private func clonedConfig(for configString: String) -> ghostty_config_t? {
        guard let template = configTemplateCache[configString] else { return nil }
        return ghostty_config_clone(template)
    }

    private func buildConfig(from configString: String) -> ghostty_config_t? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-ghostty-\(UUID().uuidString)")
            .appendingPathExtension("conf")

        guard let cfg = ghostty_config_new() else {
            return nil
        }

        do {
            try configString.write(to: tempURL, atomically: true, encoding: .utf8)
            ghostty_config_load_file(cfg, tempURL.path)
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            print("[GhosttyApp] Failed to write temp config: \(error)")
            ghostty_config_free(cfg)
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }

        ghostty_config_finalize(cfg)

        if configTemplateCache[configString] == nil,
           let template = ghostty_config_clone(cfg) {
            configTemplateCache[configString] = template
        }

        return cfg
    }

    deinit {
        if let app { ghostty_app_free(app) }
        if let config { ghostty_config_free(config) }
        for (_, template) in configTemplateCache {
            ghostty_config_free(template)
        }
    }
}
