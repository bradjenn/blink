import AppKit
import SwiftUI
import GhosttyKit

/// NSView subclass that hosts a single ghostty terminal surface.
/// Metal rendering, keyboard/mouse input, and transparency are handled here.
class TerminalSurfaceView: NSView, NSTextInputClient {

    private let ghosttyApp: GhosttyApp
    private var surface: ghostty_surface_t?
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?

    /// The tab ID this surface belongs to.
    let tabId: String
    /// The working directory for the shell.
    private let workingDirectory: String
    /// Called when the shell process exits.
    var onClose: ((String) -> Void)?

    // MARK: - Init

    private let placeholderBg: String

    init(app: GhosttyApp, tabId: String, workingDirectory: String, placeholderBg: String = "#000000") {
        self.ghosttyApp = app
        self.tabId = tabId
        self.workingDirectory = workingDirectory
        self.placeholderBg = placeholderBg
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // Layer setup for transparency — Metal renders text at full opacity
        // independently from the background, so transparent bg + crisp text works.
        wantsLayer = true
        layer?.isOpaque = false

        // Placeholder background — prevents wallpaper flash before Metal starts rendering.
        // Cleared in createSurface() once the Ghostty renderer takes over.
        layer?.backgroundColor = NSColor(Color(hex: placeholderBg)).cgColor

        updateTrackingAreas()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Surface Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard surface == nil, let _ = window, let app = ghosttyApp.app else { return }
        createSurface(app: app)
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

        // Set working directory — withCString ensures the C string lives through ghostty_surface_new
        workingDirectory.withCString { cPath in
            cfg.working_directory = cPath
            surface = ghostty_surface_new(app, &cfg)
        }
        if surface == nil {
            print("[TerminalSurfaceView] Failed to create surface")
            return
        }

        // Set initial size in framebuffer pixels (not points)
        let fbSize = convertToBacking(frame.size)
        ghostty_surface_set_size(surface, UInt32(fbSize.width), UInt32(fbSize.height))

        // Clear placeholder background — Metal renderer takes over now
        layer?.backgroundColor = nil
    }

    // MARK: - View Properties

    override var isOpaque: Bool { false }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, true)
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

    // MARK: - Resize

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface else { return }
        let fbSize = convertToBacking(newSize)
        ghostty_surface_set_size(surface, UInt32(fbSize.width), UInt32(fbSize.height))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let surface, let window else { return }
        let scale = window.backingScaleFactor
        ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))
        let fbSize = convertToBacking(frame.size)
        ghostty_surface_set_size(surface, UInt32(fbSize.width), UInt32(fbSize.height))
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
                var key_ev = Self.buildKeyEvent(action: action, event: event)
                _ = ghostty_surface_key(surface, key_ev)
            }
        } else {
            var key_ev = Self.buildKeyEvent(action: action, event: event)
            key_ev.composing = markedText.length > 0
            _ = ghostty_surface_key(surface, key_ev)
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
            return
        }

        // Outside keyDown (e.g. paste), send text directly
        guard let surface else { return }
        chars.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(chars.utf8.count))
        }
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

    // MARK: - Focus

    /// Grab keyboard focus for this terminal.
    func focus() {
        guard let window else { return }
        window.makeFirstResponder(self)
    }

    // MARK: - Cleanup

    /// Free the ghostty surface. Called by SurfaceManager on tab close.
    func teardown() {
        if let surface {
            ghostty_surface_free(surface)
        }
        surface = nil
    }

    deinit {
        teardown()
    }
}
