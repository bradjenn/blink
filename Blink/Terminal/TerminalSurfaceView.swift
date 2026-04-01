import AppKit
import SwiftUI
import GhosttyKit
import OSLog
import QuartzCore

enum SwipeNavigationDirection {
    case previous
    case next
}

private enum TerminalPerf {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.blink.app",
        category: "TerminalPerformance"
    )
    private static let signposter = OSSignposter(logger: logger)
    private static let signpostsKey = "blink.perf.signposts"

    static var signpostsEnabled: Bool {
        UserDefaults.standard.bool(forKey: signpostsKey)
    }

    static func begin(_ name: StaticString) -> OSSignpostIntervalState? {
        guard signpostsEnabled else { return nil }
        return signposter.beginInterval(name)
    }

    static func end(_ name: StaticString, _ state: OSSignpostIntervalState?) {
        guard let state else { return }
        signposter.endInterval(name, state)
    }

    static func emit(_ name: StaticString) {
        guard signpostsEnabled else { return }
        signposter.emitEvent(name)
    }
}

private extension NSScreen {
    var displayID: UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let v = deviceDescription[key] as? UInt32 { return v }
        if let v = deviceDescription[key] as? Int { return UInt32(v) }
        if let v = deviceDescription[key] as? NSNumber { return v.uint32Value }
        return nil
    }
}

@MainActor
protocol TerminalSurfaceCommandSink: AnyObject {
    func setContentScale(x: Double, y: Double)
    func setSize(width: UInt32, height: UInt32)
}

struct TerminalSubmittedLineBuffer {
    private var characters: [Character] = []
    private var cursor = 0

    mutating func insert(_ text: String) -> Bool {
        var shouldSubmit = false
        for character in text {
            if character == "\r" || character == "\n" {
                shouldSubmit = true
                continue
            }
            characters.insert(character, at: cursor)
            cursor += 1
        }
        return shouldSubmit
    }

    mutating func handleKeyCode(_ keyCode: UInt16) {
        switch keyCode {
        case 51:
            deleteBackward()
        case 117:
            deleteForward()
        case 123:
            moveLeft()
        case 124:
            moveRight()
        case 115:
            moveHome()
        case 119:
            moveEnd()
        default:
            break
        }
    }

    mutating func submit() -> String? {
        let line = String(characters).trimmingCharacters(in: .whitespacesAndNewlines)
        clear()
        guard !line.isEmpty else { return nil }
        return line
    }

    mutating func clear() {
        characters.removeAll(keepingCapacity: true)
        cursor = 0
    }

    var currentLine: String {
        String(characters)
    }

    private mutating func deleteBackward() {
        guard cursor > 0 else { return }
        characters.remove(at: cursor - 1)
        cursor -= 1
    }

    private mutating func deleteForward() {
        guard cursor < characters.count else { return }
        characters.remove(at: cursor)
    }

    private mutating func moveLeft() {
        guard cursor > 0 else { return }
        cursor -= 1
    }

    private mutating func moveRight() {
        guard cursor < characters.count else { return }
        cursor += 1
    }

    private mutating func moveHome() {
        cursor = 0
    }

    private mutating func moveEnd() {
        cursor = characters.count
    }
}

private final class GhosttyTerminalSurfaceCommandSink: TerminalSurfaceCommandSink {
    private let surface: ghostty_surface_t

    init(surface: ghostty_surface_t) {
        self.surface = surface
    }

    func setContentScale(x: Double, y: Double) {
        ghostty_surface_set_content_scale(surface, x, y)
    }

    func setSize(width: UInt32, height: UInt32) {
        ghostty_surface_set_size(surface, width, height)
    }
}

/// NSView subclass that hosts a single ghostty terminal surface.
/// Metal rendering, keyboard/mouse input, and transparency are handled here.
class TerminalSurfaceView: NSView, NSTextInputClient {

    private let ghosttyApp: GhosttyApp
    private var surface: ghostty_surface_t?
    private var isTearingDown = false
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?

    /// The tab ID this surface belongs to.
    let tabId: String
    /// Stable pane ID used across restored sessions.
    private let paneId: String
    /// The project ID this surface belongs to.
    private let projectId: String
    /// The project name this surface belongs to.
    private let projectName: String
    /// Optional directory that contains Blink-installed CLI wrappers.
    private let hookScriptDirectoryPath: String?
    /// Optional ZDOTDIR wrapper directory for shell integration.
    private let hookShellIntegrationDirectoryPath: String?
    /// Optional event directory used for Claude hook integration.
    private let hookEventDirectoryPath: String?
    /// The working directory for the shell.
    private let workingDirectory: String
    /// Optional command to run instead of the default shell.
    private let command: String?
    /// Called when the shell process exits.
    var onClose: ((String) -> Void)?
    /// Called once after the terminal surface is created and attached.
    var onReady: ((String) -> Void)?
    /// Called when the user performs a window-switch gesture.
    var onSwipeNavigation: ((SwipeNavigationDirection) -> Void)?
    /// Called when the user interacts with the surface directly.
    var onInteraction: (() -> Void)?
    /// Called whenever the user submits a line in the terminal.
    var onSubmittedLine: ((String) -> Void)?

    private var swipeNavigationAccumulatedX: CGFloat = 0
    private var swipeNavigationDirection: SwipeNavigationDirection?
    private var lastSwipeNavigationTimestamp: TimeInterval = 0
    private var submittedLineBuffer = TerminalSubmittedLineBuffer()
    private var pendingSurfaceSize: CGSize?
    private var deferredSurfaceSizeRetryQueued = false
    private var visibleInUI = true
    private var needsSurfaceRecoveryOnAttach = false
    private weak var observedWindow: NSWindow?
    private var windowScreenObserver: NSObjectProtocol?
    private var lastDisplayID: UInt32?
    private var lastSurfacePixelSize: CGSize?
    private var lastSurfaceScale: CGSize?
    private var lastDrawableSize: CGSize = .zero
    private var lastLayerContentsScale: CGFloat?
    var commandSinkOverride: TerminalSurfaceCommandSink?

    private static let defaultShellPATHEntries = [
        ".local/bin",
        "bin",
    ]

    private static let systemPATHEntries = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    private static let swipeNavigationThreshold: CGFloat = 72
    private static let swipeNavigationCooldown: TimeInterval = 0.25
    private static let swipeNavigationHorizontalBias: CGFloat = 1.5

    // MARK: - Init

    init(
        app: GhosttyApp,
        tabId: String,
        paneId: String,
        projectId: String,
        projectName: String,
        hookScriptDirectoryPath: String? = nil,
        hookShellIntegrationDirectoryPath: String? = nil,
        hookEventDirectoryPath: String? = nil,
        workingDirectory: String,
        command: String? = nil
    ) {
        self.ghosttyApp = app
        self.tabId = tabId
        self.paneId = paneId
        self.projectId = projectId
        self.projectName = projectName
        self.hookScriptDirectoryPath = hookScriptDirectoryPath
        self.hookShellIntegrationDirectoryPath = hookShellIntegrationDirectoryPath
        self.hookEventDirectoryPath = hookEventDirectoryPath
        self.workingDirectory = workingDirectory
        self.command = command
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // Layer setup for transparency — Metal renders text at full opacity
        // independently from the background, so transparent bg + crisp text works.
        wantsLayer = true
        layer?.isOpaque = false
        layer?.masksToBounds = true

        // Accept file and text drops from Finder and other apps
        registerForDraggedTypes([.fileURL, .string])

        updateTrackingAreas()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func makeBackingLayer() -> CALayer {
        let metalLayer = CAMetalLayer()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = false
        return metalLayer
    }

    // MARK: - Surface Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowObservation()
        updateSurfaceVisibility()

        guard !isTearingDown else { return }

        if surface == nil, let window, let app = ghosttyApp.app {
            _ = window
            createSurface(app: app)
            return
        }

        guard window != nil else {
            needsSurfaceRecoveryOnAttach = true
            return
        }

        if let surface {
            applySurfaceDisplayID(surface, force: true)
            recoverSurfaceIfNeeded(surface, reason: "WindowAttachRecovery")
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateSurfaceVisibility()
        if superview == nil {
            needsSurfaceRecoveryOnAttach = true
        }
    }

    private func createSurface(app: ghostty_app_t) {
        var cfg = ghostty_surface_config_new()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(self).toOpaque()
            )
        )
        cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        cfg.scale_factor = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0)

        // Both command tabs and normal shells are wrapped with `env -u NO_COLOR`
        // to strip the NO_COLOR variable that may be inherited from the parent
        // process. Ghostty's env_vars API can only add/override — not unset —
        // so we use `env -u` to guarantee NO_COLOR is absent.
        var envVars: [ghostty_env_var_s] = [
            ghostty_env_var_s(key: strdup("TERM"), value: strdup("xterm-256color")),
            ghostty_env_var_s(key: strdup("COLORTERM"), value: strdup("truecolor")),
            // Some CLIs only emit OSC-8 hyperlinks when the terminal program is
            // advertised explicitly. Blink embeds Ghostty, so expose that here.
            ghostty_env_var_s(key: strdup("TERM_PROGRAM"), value: strdup("Ghostty")),
            ghostty_env_var_s(key: strdup("PATH"), value: strdup(shellPATH())),
            ghostty_env_var_s(key: strdup("BLINK_TAB_ID"), value: strdup(tabId)),
            ghostty_env_var_s(key: strdup("BLINK_PANE_ID"), value: strdup(paneId)),
            ghostty_env_var_s(key: strdup("BLINK_PROJECT_ID"), value: strdup(projectId)),
            ghostty_env_var_s(key: strdup("BLINK_PROJECT_NAME"), value: strdup(projectName)),
            ghostty_env_var_s(key: strdup("BLINK_PROJECT_PATH"), value: strdup(workingDirectory)),
        ]
        if let hookEventDirectoryPath, !hookEventDirectoryPath.isEmpty {
            envVars.append(
                ghostty_env_var_s(
                    key: strdup("BLINK_HOOK_EVENT_DIR"),
                    value: strdup(hookEventDirectoryPath)
                )
            )
        }
        if let hookScriptDirectoryPath, !hookScriptDirectoryPath.isEmpty {
            let wrapperPath = (hookScriptDirectoryPath as NSString).appendingPathComponent("claude")
            envVars.append(
                ghostty_env_var_s(
                    key: strdup("BLINK_CLAUDE_WRAPPER_PATH"),
                    value: strdup(wrapperPath)
                )
            )
        }
        if let hookShellIntegrationDirectoryPath, !hookShellIntegrationDirectoryPath.isEmpty {
            envVars.append(
                ghostty_env_var_s(
                    key: strdup("BLINK_SHELL_INTEGRATION"),
                    value: strdup("1")
                )
            )
            envVars.append(
                ghostty_env_var_s(
                    key: strdup("BLINK_SHELL_INTEGRATION_DIR"),
                    value: strdup(hookShellIntegrationDirectoryPath)
                )
            )
        }

        let shell = UserDefaults.standard.string(forKey: "blink.shell")
            ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = URL(fileURLWithPath: shell).lastPathComponent
        if shellName == "zsh",
           let hookShellIntegrationDirectoryPath, !hookShellIntegrationDirectoryPath.isEmpty {
            if let candidateZdotdir = ProcessInfo.processInfo.environment["ZDOTDIR"],
               !candidateZdotdir.isEmpty {
                envVars.append(
                    ghostty_env_var_s(
                        key: strdup("BLINK_ZSH_ZDOTDIR"),
                        value: strdup(candidateZdotdir)
                    )
                )
            }
            envVars.append(
                ghostty_env_var_s(
                    key: strdup("ZDOTDIR"),
                    value: strdup(hookShellIntegrationDirectoryPath)
                )
            )
        }

        // Set working directory and optional command
        let createWithConfig = { [self] (cmdPtr: UnsafePointer<CChar>?) in
            workingDirectory.withCString { cPath in
                cfg.working_directory = cPath
                cfg.command = cmdPtr
                envVars.withUnsafeMutableBufferPointer { buf in
                    cfg.env_vars = buf.baseAddress
                    cfg.env_var_count = buf.count
                    surface = ghostty_surface_new(app, &cfg)
                }
            }
        }
        let wrapped: String
        if let command {
            // Command tabs: non-interactive login shell running a specific command
            wrapped = "env -u NO_COLOR \(Self.shellQuote(shell)) -l -c \(Self.shellQuote(command))"
        } else {
            // Normal tabs: interactive login shell (no -c flag, so the shell
            // detects the PTY and enters interactive mode with full job control)
            wrapped = "env -u NO_COLOR \(Self.shellQuote(shell)) -l"
        }
        wrapped.withCString { createWithConfig($0) }

        // Free strdup'd strings
        for ev in envVars {
            free(UnsafeMutablePointer(mutating: ev.key))
            free(UnsafeMutablePointer(mutating: ev.value))
        }
        if surface == nil {
            print("[TerminalSurfaceView] Failed to create surface")
            return
        }

        if let surface {
            applySurfaceDisplayID(surface, force: true)
            updateSurfaceVisibility()
        }

        // Set initial size in framebuffer pixels (not points)
        syncSurfaceSize()

        // Auto-focus after surface creation — use DispatchQueue (not Task)
        // so the focus call lands at a deterministic point in the run loop,
        // before SwiftUI's cooperative scheduler can interleave focus-cleanup.
        DispatchQueue.main.async { [weak self] in
            self?.focus()
            if let self {
                self.onReady?(self.tabId)
            }
        }
    }

    private func shellPATH() -> String {
        var entries: [String] = []
        var seen = Set<String>()

        func append(_ entry: String?) {
            guard let raw = entry?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  !seen.contains(raw) else { return }
            seen.insert(raw)
            entries.append(raw)
        }

        let home = NSHomeDirectory()
        for relativePath in Self.defaultShellPATHEntries {
            append((home as NSString).appendingPathComponent(relativePath))
        }

        if let hookScriptDirectoryPath {
            append(hookScriptDirectoryPath)
        }

        if let inheritedPATH = ProcessInfo.processInfo.environment["PATH"] {
            for entry in inheritedPATH.split(separator: ":") {
                append(String(entry))
            }
        }

        for entry in Self.systemPATHEntries {
            append(entry)
        }

        return entries.joined(separator: ":")
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    // MARK: - View Properties

    override var isOpaque: Bool { false }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, true)
            applySurfaceDisplayID(surface, force: true)
            recoverSurfaceIfNeeded(surface, reason: "FocusRecovery")
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    @IBAction func copy(_ sender: Any?) {
        _ = performBindingAction("copy_to_clipboard")
    }

    @IBAction func paste(_ sender: Any?) {
        _ = performBindingAction("paste_from_clipboard")
    }

    @IBAction func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    // MARK: - Resize

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncSurfaceSize()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        syncSurfaceSize()
    }

    override func layout() {
        super.layout()
        syncSurfaceSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncSurfaceSize()
    }

    private func syncSurfaceSize() {
        let interval = TerminalPerf.begin("SurfaceResizeSync")
        defer { TerminalPerf.end("SurfaceResizeSync", interval) }

        guard let commandSink = surfaceCommandSink else { return }
        let logicalSize = resolvedSurfaceSize(preferred: nil)
        guard logicalSize.width > 0, logicalSize.height > 0 else { return }
        pendingSurfaceSize = logicalSize

        if Self.shouldDeferSurfaceResizeForActiveDrag() {
            TerminalPerf.emit("SurfaceResizeDeferred")
            scheduleDeferredSurfaceSizeRetryIfNeeded()
            return
        }

        let fbSize = convertToBacking(NSRect(origin: .zero, size: logicalSize)).size
        let pixelSize = CGSize(
            width: floor(max(0, fbSize.width)),
            height: floor(max(0, fbSize.height))
        )
        guard pixelSize.width > 0, pixelSize.height > 0 else { return }

        let xScale = pixelSize.width / logicalSize.width
        let yScale = pixelSize.height / logicalSize.height
        let surfaceScale = CGSize(width: xScale, height: yScale)
        let layerScale = window?.backingScaleFactor ?? max(xScale, yScale)

        if !nearlyEqual(surfaceScale, lastSurfaceScale) {
            commandSink.setContentScale(x: xScale, y: yScale)
            lastSurfaceScale = surfaceScale
            TerminalPerf.emit("SurfaceScaleChanged")
        }

        if pixelSize != lastSurfacePixelSize {
            commandSink.setSize(width: UInt32(pixelSize.width), height: UInt32(pixelSize.height))
            lastSurfacePixelSize = pixelSize
            TerminalPerf.emit("SurfacePixelSizeChanged")
        }

        if lastLayerContentsScale != layerScale {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = layerScale
            layer?.masksToBounds = true
            if let metalLayer = layer as? CAMetalLayer,
               metalLayer.drawableSize != pixelSize || lastDrawableSize != pixelSize {
                metalLayer.drawableSize = pixelSize
                lastDrawableSize = pixelSize
            }
            CATransaction.commit()
            lastLayerContentsScale = layerScale
        } else if let metalLayer = layer as? CAMetalLayer,
                  metalLayer.drawableSize != pixelSize || lastDrawableSize != pixelSize {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            metalLayer.drawableSize = pixelSize
            CATransaction.commit()
            lastDrawableSize = pixelSize
        }
    }

    private func resolvedSurfaceSize(preferred size: CGSize?) -> CGSize {
        if let size, size.width > 0, size.height > 0 {
            return size
        }

        let currentBounds = bounds.size
        if currentBounds.width > 0, currentBounds.height > 0 {
            return currentBounds
        }

        if let pendingSurfaceSize,
           pendingSurfaceSize.width > 0,
           pendingSurfaceSize.height > 0 {
            return pendingSurfaceSize
        }

        return currentBounds
    }

    private static func isDragResizeEvent(_ eventType: NSEvent.EventType?) -> Bool {
        switch eventType {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return true
        default:
            return false
        }
    }

    private static func shouldDeferSurfaceResizeForActiveDrag() -> Bool {
        isDragResizeEvent(NSApp.currentEvent?.type)
    }

    private func scheduleDeferredSurfaceSizeRetryIfNeeded() {
        guard window != nil else { return }
        guard !deferredSurfaceSizeRetryQueued else { return }
        deferredSurfaceSizeRetryQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.deferredSurfaceSizeRetryQueued = false
            self.syncSurfaceSize()
        }
    }

    private func nearlyEqual(_ lhs: CGSize, _ rhs: CGSize?, epsilon: CGFloat = 0.0001) -> Bool {
        guard let rhs else { return false }
        return abs(lhs.width - rhs.width) <= epsilon && abs(lhs.height - rhs.height) <= epsilon
    }

    func setVisibleInUI(_ visible: Bool) {
        guard visibleInUI != visible else { return }
        visibleInUI = visible
        if !visible {
            needsSurfaceRecoveryOnAttach = true
        }
        updateSurfaceVisibility()
    }

    private func updateSurfaceVisibility() {
        guard let surface else { return }
        let isVisible = visibleInUI
            && window != nil
            && superview != nil
            && !isHiddenOrHasHiddenAncestor
        ghostty_surface_set_occlusion(surface, isVisible)
    }

    private func updateWindowObservation() {
        guard observedWindow !== window else { return }

        if let windowScreenObserver {
            NotificationCenter.default.removeObserver(windowScreenObserver)
            self.windowScreenObserver = nil
        }

        observedWindow = window
        guard let window else { return }

        windowScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.windowDidChangeScreen()
        }
    }

    private func windowDidChangeScreen() {
        guard let surface else { return }
        let displayChanged = applySurfaceDisplayID(surface, force: true)
        if displayChanged {
            recoverSurfaceIfNeeded(surface, reason: "ScreenChangeRecovery")
        } else {
            syncSurfaceSize()
        }
    }

    @discardableResult
    private func applySurfaceDisplayID(_ surface: ghostty_surface_t, force: Bool) -> Bool {
        guard let displayID = (window?.screen ?? NSScreen.main)?.displayID,
              displayID != 0 else { return false }
        guard force || lastDisplayID != displayID else { return false }
        ghostty_surface_set_display_id(surface, displayID)
        lastDisplayID = displayID
        TerminalPerf.emit("SurfaceDisplayIDChanged")
        return true
    }

    private func recoverSurfaceIfNeeded(_ surface: ghostty_surface_t, reason: StaticString) {
        guard needsSurfaceRecoveryOnAttach else { return }
        let interval = TerminalPerf.begin(reason)
        syncSurfaceSize()
        ghostty_surface_refresh(surface)
        needsSurfaceRecoveryOnAttach = false
        TerminalPerf.emit("SurfaceRecoveryRefresh")
        TerminalPerf.end(reason, interval)
    }

    private var surfaceCommandSink: TerminalSurfaceCommandSink? {
        if let commandSinkOverride {
            return commandSinkOverride
        }

        guard let surface else { return nil }
        return GhosttyTerminalSurfaceCommandSink(surface: surface)
    }

    // MARK: - Tracking Areas

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
            owner: self,
            userInfo: nil
        ))
        super.updateTrackingAreas()
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            interpretKeyEvents([event])
            return
        }

        let action: ghostty_input_action_e = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        // Collect text from input method system
        keyTextAccumulator = []
        interpretKeyEvents([event])
        let accumulatedText = keyTextAccumulator
        keyTextAccumulator = nil

        // Build key event with all required fields
        if let texts = accumulatedText, !texts.isEmpty {
            let combined = texts.joined()
            // Only set text for printable characters (codepoint >= 0x20).
            // Control characters are encoded by Ghostty itself.
            if let first = combined.utf8.first, first >= 0x20 {
                combined.withCString { ptr in
                    var key_ev = Self.buildKeyEvent(action: action, event: event)
                    key_ev.text = ptr
                    _ = ghostty_surface_key(surface, key_ev)
                }
            } else {
                let key_ev = Self.buildKeyEvent(action: action, event: event)
                _ = ghostty_surface_key(surface, key_ev)
            }
        } else {
            var key_ev = Self.buildKeyEvent(action: action, event: event)
            key_ev.composing = markedText.length > 0
            _ = ghostty_surface_key(surface, key_ev)
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            submitBufferedLineIfNeeded()
        } else {
            submittedLineBuffer.handleKeyCode(event.keyCode)
        }

    }

    override func keyUp(with event: NSEvent) {
        guard let surface else { return }
        let key_ev = Self.buildKeyEvent(action: GHOSTTY_ACTION_RELEASE, event: event)
        _ = ghostty_surface_key(surface, key_ev)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else { return }
        let action: ghostty_input_action_e =
            event.modifierFlags.contains(Self.modifierFlag(for: event.keyCode))
                ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        let key_ev = Self.buildKeyEvent(action: action, event: event)
        _ = ghostty_surface_key(surface, key_ev)
    }

    /// Build a ghostty_input_key_s with all required fields from an NSEvent.
    private static func buildKeyEvent(
        action: ghostty_input_action_e,
        event: NSEvent
    ) -> ghostty_input_key_s {
        var key_ev = ghostty_input_key_s()
        key_ev.action = action
        key_ev.keycode = UInt32(event.keyCode)
        key_ev.mods = translateMods(event.modifierFlags)

        // consumed_mods: modifiers that contributed to text translation.
        // Heuristic from Ghostty: control and command never contribute,
        // assume everything else (shift, option, caps) did.
        key_ev.consumed_mods = translateMods(
            event.modifierFlags.subtracting([.control, .command])
        )

        // unshifted_codepoint: the character without any modifiers applied.
        // Used by Ghostty for keybinding resolution.
        key_ev.unshifted_codepoint = 0
        if event.type == .keyDown || event.type == .keyUp {
            if let chars = event.characters(byApplyingModifiers: []),
               let codepoint = chars.unicodeScalars.first {
                key_ev.unshifted_codepoint = codepoint.value
            }
        }

        key_ev.text = nil
        key_ev.composing = false
        return key_ev
    }

    // Suppress system alert sound for unhandled key commands
    override func doCommand(by selector: Selector) {
        // No-op — prevents NSBeep for commands like moveUp:, moveDown:, etc.
    }

    // MARK: - NSTextInputClient

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: markedText.length)
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let v as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: v)
        case let v as String:
            markedText = NSMutableAttributedString(string: v)
        default:
            return
        }
    }

    func unmarkText() {
        markedText = NSMutableAttributedString()
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        var chars = ""
        switch string {
        case let v as NSAttributedString:
            chars = v.string
        case let v as String:
            chars = v
        default:
            return
        }

        unmarkText()

        // If in keyDown flow, accumulate text — it will be sent via ghostty_surface_key
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(chars)
            recordSubmittedLineText(chars)
            return
        }

        // Outside keyDown (e.g. paste), send text directly
        recordSubmittedLineText(chars)
        guard let surface else { return }
        chars.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(chars.utf8.count))
        }
    }

    private func recordSubmittedLineText(_ text: String) {
        guard onSubmittedLine != nil, !text.isEmpty else { return }
        if submittedLineBuffer.insert(text) {
            submitBufferedLineIfNeeded()
        }
    }

    private func submitBufferedLineIfNeeded() {
        guard onSubmittedLine != nil else {
            submittedLineBuffer.clear()
            return
        }

        guard let line = submittedLineBuffer.submit() else { return }
        onSubmittedLine?(line)
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        let viewRect = NSRect(x: 0, y: 0, width: 0, height: 0)
        let winRect = convert(viewRect, to: nil)
        return window.convertToScreen(winRect)
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        onInteraction?()
        focus()
        let mods = Self.translateMods(event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = Self.translateMods(event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return }
        onInteraction?()
        let mods = Self.translateMods(event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = Self.translateMods(event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        let mods = Self.translateMods(event.modifierFlags)
        // Ghostty uses top-left origin, AppKit uses bottom-left
        ghostty_surface_mouse_pos(surface, Double(pos.x), Double(frame.height - pos.y), mods)
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        if handleSwipeNavigation(with: event) {
            return
        }
        TerminalPerf.emit("SurfaceScrollWheel")
        // ghostty_input_scroll_mods_t is a plain int bitmask, not a struct.
        // Bit 0 = precision scrolling (trackpad vs mouse wheel).
        var scrollMods: ghostty_input_scroll_mods_t = 0
        if event.hasPreciseScrollingDeltas {
            scrollMods |= 1
        }
        ghostty_surface_mouse_scroll(
            surface,
            event.scrollingDeltaX,
            event.scrollingDeltaY,
            scrollMods
        )
    }

    private func handleSwipeNavigation(with event: NSEvent) -> Bool {
        if event.phase.contains(.began) {
            resetSwipeNavigation()
        }

        let isHorizontalSwipe = event.hasPreciseScrollingDeltas
            && event.momentumPhase.isEmpty
            && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * Self.swipeNavigationHorizontalBias

        guard isHorizontalSwipe else {
            if !event.hasPreciseScrollingDeltas
                || !event.momentumPhase.isEmpty
                || event.phase.contains(.ended)
                || event.phase.contains(.cancelled) {
                resetSwipeNavigation()
            }
            return false
        }

        let direction: SwipeNavigationDirection = event.scrollingDeltaX > 0 ? .previous : .next
        if swipeNavigationDirection != direction {
            swipeNavigationDirection = direction
            swipeNavigationAccumulatedX = 0
        }

        swipeNavigationAccumulatedX += abs(event.scrollingDeltaX)

        if event.timestamp - lastSwipeNavigationTimestamp >= Self.swipeNavigationCooldown,
           swipeNavigationAccumulatedX >= Self.swipeNavigationThreshold {
            lastSwipeNavigationTimestamp = event.timestamp
            swipeNavigationAccumulatedX = 0
            onSwipeNavigation?(direction)
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            resetSwipeNavigation()
        }

        return true
    }

    private func resetSwipeNavigation() {
        swipeNavigationAccumulatedX = 0
        swipeNavigationDirection = nil
    }

    // MARK: - Modifier Translation

    private static func translateMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE
        if flags.contains(.shift) { mods = ghostty_input_mods_e(mods.rawValue | GHOSTTY_MODS_SHIFT.rawValue) }
        if flags.contains(.control) { mods = ghostty_input_mods_e(mods.rawValue | GHOSTTY_MODS_CTRL.rawValue) }
        if flags.contains(.option) { mods = ghostty_input_mods_e(mods.rawValue | GHOSTTY_MODS_ALT.rawValue) }
        if flags.contains(.command) { mods = ghostty_input_mods_e(mods.rawValue | GHOSTTY_MODS_SUPER.rawValue) }
        if flags.contains(.capsLock) { mods = ghostty_input_mods_e(mods.rawValue | GHOSTTY_MODS_CAPS.rawValue) }
        return mods
    }

    private static func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags {
        switch keyCode {
        case 0x39: return .capsLock
        case 0x38, 0x3C: return .shift
        case 0x3B, 0x3E: return .control
        case 0x3A, 0x3D: return .option
        case 0x37, 0x36: return .command
        default: return []
        }
    }

    // MARK: - Drag and Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if pb.canReadObject(forClasses: [NSURL.self, NSString.self]) {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard

        // File URLs → shell-escaped absolute paths
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            let escaped = urls.map { Self.shellQuote($0.path) }
            sendText(escaped.joined(separator: " "))
            return true
        }

        // Plain text fallback
        if let text = pb.string(forType: .string), !text.isEmpty {
            sendText(text)
            return true
        }

        return false
    }

    // MARK: - Text Input

    /// Send a string to the terminal as if it were typed.
    func sendText(_ text: String) {
        recordSubmittedLineText(text)
        guard let surface else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
    }

    // MARK: - Focus

    /// Grab keyboard focus for this terminal.
    func focus() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(self)
    }

    func completeClipboardRequest(
        _ string: String,
        state: UnsafeMutableRawPointer,
        confirmed: Bool = false
    ) {
        guard let surface else { return }
        string.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, confirmed)
        }
    }

    private func performBindingAction(_ action: String) -> Bool {
        guard let surface else { return false }
        return action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
    }

    // MARK: - Cleanup

    /// Free the ghostty surface. Called by SurfaceManager on tab close.
    func teardown() {
        guard !isTearingDown else { return }
        isTearingDown = true

        guard let surface else { return }

        self.surface = nil
        onClose = nil
        onReady = nil
        onSwipeNavigation = nil
        onInteraction = nil
        onSubmittedLine = nil
        if let windowScreenObserver {
            NotificationCenter.default.removeObserver(windowScreenObserver)
            self.windowScreenObserver = nil
        }
        observedWindow = nil

        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
        removeFromSuperview()

        // Free the surface on the next main-runloop turn so AppKit/Metal can
        // finish the current frame commit before Ghostty tears renderer state down.
        DispatchQueue.main.async { [surface] in
            withExtendedLifetime(self) {
                ghostty_surface_free(surface)
            }
        }
    }

    deinit {
        teardown()
    }
}

extension TerminalSurfaceView: NSUserInterfaceValidations {
    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        guard let surface else { return false }

        switch item.action {
        case #selector(copy(_:)):
            return ghostty_surface_has_selection(surface)
        case #selector(paste(_:)), #selector(pasteAsPlainText(_:)):
            return NSPasteboard.general.string(forType: .string) != nil
        default:
            return true
        }
    }
}
