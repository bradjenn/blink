import Foundation
import GhosttyKit

/// Wraps the ghostty_app_t lifecycle. One instance per app.
/// Blink controls all terminal settings — no Ghostty config files are loaded.
final class GhosttyApp {
    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?

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

        // Write Blink's terminal settings to a temp file and load it.
        // The ghostty config API only supports loading from files, not programmatic set.
        let configString = "background-opacity = 0.85\n"

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

        // Stub callbacks — return false/no-op for PoC
        runtime.action_cb = { _, _, _ in return false }
        runtime.read_clipboard_cb = { _, _, _ in return false }
        runtime.confirm_read_clipboard_cb = { _, _, _, _ in }
        runtime.write_clipboard_cb = { _, _, _, _, _ in }
        runtime.close_surface_cb = { _, _ in }

        // Create the app
        self.app = ghostty_app_new(&runtime, cfg)
        if self.app == nil {
            print("[GhosttyApp] Failed to create ghostty app")
        }
    }

    deinit {
        if let app { ghostty_app_free(app) }
        if let config { ghostty_config_free(config) }
    }
}
