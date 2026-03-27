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
    // These are opaque C pointers with no Swift-managed state.
    // Marked nonisolated(unsafe) so deinit can free them without
    // violating @MainActor isolation in Swift 6 strict concurrency.
    nonisolated(unsafe) private(set) var app: ghostty_app_t?
    nonisolated(unsafe) private(set) var config: ghostty_config_t?
    nonisolated(unsafe) private var configTemplateCache: [String: ghostty_config_t] = [:]
    private var activeConfigKey: String?

    /// Weak refs for routing callbacks back to Swift objects.
    weak var store: AppStore?
    weak var surfaceManager: SurfaceManager?

    /// Per-tab debounce timers to coalesce rapid SET_TITLE updates.
    private var titleDebounceTimers: [String: Timer] = [:]

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

                    // Debounce: coalesce rapid title updates into one mutation
                    // after 100ms of quiet. Prevents SwiftUI body recomputation
                    // storms during scrollback / rapid output.
                    ghostty.titleDebounceTimers[tabId]?.invalidate()
                    ghostty.titleDebounceTimers[tabId] = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak ghostty] _ in
                        DispatchQueue.main.async {
                            guard let store = ghostty?.store else { return }
                            store.handleTerminalTitleUpdate(titleStr, for: tabId)
                        }
                    }
                }
                return true

            case GHOSTTY_ACTION_OPEN_URL:
                guard target.tag == GHOSTTY_TARGET_SURFACE else { return false }
                let surface = target.target.surface
                guard let urlPtr = action.action.open_url.url else { return false }
                let urlBytes = UnsafeBufferPointer(
                    start: UnsafeRawPointer(urlPtr).assumingMemoryBound(to: UInt8.self),
                    count: Int(action.action.open_url.len)
                )
                let rawURL = String(decoding: urlBytes, as: UTF8.self)

                guard let viewPtr = ghostty_surface_userdata(surface) else { return false }
                let view = Unmanaged<TerminalSurfaceView>.fromOpaque(viewPtr).takeUnretainedValue()
                let tabId = view.tabId

                DispatchQueue.main.async {
                    ghostty.handleOpenURL(rawURL, for: tabId)
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

        // Note: read_clipboard_cb and confirm_read_clipboard_cb must
        // return synchronously to Ghostty. They access NSPasteboard (main-
        // thread-only) and call completeClipboardRequest which feeds data
        // back into the Ghostty C API. Ghostty calls these from
        // ghostty_app_tick which is dispatched to main in wakeup_cb,
        // so they already execute on the main thread.
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
            guard let content, len > 0 else { return }

            // Extract clipboard data before dispatching — the pointers
            // are only valid for the duration of this callback.
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

            // NSPasteboard is main-thread-only — dispatch writes there
            DispatchQueue.main.async {
                guard let pasteboard = NSPasteboard.blink(clipboard) else { return }
                pasteboard.declareTypes(items.map(\.type), owner: nil)
                for item in items {
                    pasteboard.setString(item.value, forType: item.type)
                }
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

    private func handleOpenURL(_ rawURL: String, for tabId: String) {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              let store,
              let projectId = store.tabsById[tabId]?.projectId else {
            return
        }

        if let editorTarget = resolvedEditorTarget(from: trimmedURL, projectId: projectId, store: store) {
            store.openFileInEditor(
                projectId: projectId,
                path: editorTarget.path,
                line: editorTarget.line
            )
            return
        }

        guard let url = URL(string: trimmedURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func resolvedEditorTarget(
        from rawURL: String,
        projectId: String,
        store: AppStore
    ) -> (path: String, line: Int?)? {
        if let url = URL(string: rawURL) {
            if url.scheme == "file" {
                let path = url.path.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else { return nil }
                return (path, resolvedLineNumber(from: url))
            }

            if url.scheme == "blink-file",
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let path = components.queryItems?.first(where: { $0.name == "path" })?.value {
                let line = components.queryItems?
                    .first(where: { $0.name == "line" })?
                    .value
                    .flatMap(Int.init)
                return (resolvedProjectPath(path, projectId: projectId, store: store), line)
            }

            if url.scheme != nil {
                return nil
            }
        }

        let line = parseLineNumber(from: rawURL)
        let basePath = rawURL
            .replacingOccurrences(of: #"#L\d+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #":\d+(?::\d+)?$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !basePath.isEmpty else { return nil }
        return (resolvedProjectPath(basePath, projectId: projectId, store: store), line)
    }

    private func resolvedProjectPath(_ rawPath: String, projectId: String, store: AppStore) -> String {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPath.hasPrefix("/") {
            return trimmedPath
        }

        guard let project = store.projects.first(where: { $0.id == projectId }) else {
            return trimmedPath
        }

        return URL(fileURLWithPath: project.path)
            .appendingPathComponent(trimmedPath)
            .path
    }

    private func resolvedLineNumber(from url: URL) -> Int? {
        if let fragment = url.fragment,
           let line = parseLineNumber(from: fragment) {
            return line
        }

        return parseLineNumber(from: url.lastPathComponent)
    }

    private func parseLineNumber(from value: String) -> Int? {
        if let match = value.range(of: #"L(\d+)"#, options: .regularExpression) {
            let digits = value[match].drop(while: { !$0.isNumber })
            return Int(digits)
        }

        if let match = value.range(of: #":(\d+)(?::\d+)?$"#, options: .regularExpression) {
            let digits = value[match]
                .dropFirst()
                .prefix(while: \.isNumber)
            return Int(digits)
        }

        return nil
    }

    deinit {
        if let app { ghostty_app_free(app) }
        if let config { ghostty_config_free(config) }
        for (_, template) in configTemplateCache {
            ghostty_config_free(template)
        }
    }
}
