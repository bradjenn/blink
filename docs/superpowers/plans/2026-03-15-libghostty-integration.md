# libghostty Integration — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get a single GPU-accelerated terminal rendering in Blink's content area with transparent background and crisp text, powered by libghostty.

**Architecture:** Build GhosttyKit xcframework from the Ghostty fork, wrap the C API in a Swift `GhosttyApp` class, render a terminal surface via an NSView subclass wrapped in `NSViewRepresentable`, and place it in Shell.swift's content area.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit (NSView), GhosttyKit (Zig/C), Metal (via libghostty), XcodeGen

**Spec:** `docs/superpowers/specs/2026-03-15-libghostty-integration-design.md`

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `project.yml` | Modify | Add GhosttyKit framework, system framework deps, linker flags |
| `Blink/Terminal/GhosttyApp.swift` | Create | Wraps `ghostty_app_t` lifecycle, config, callbacks |
| `Blink/Terminal/TerminalSurfaceView.swift` | Create | NSView subclass hosting the Metal terminal surface |
| `Blink/Terminal/TerminalView.swift` | Create | SwiftUI `NSViewRepresentable` wrapper |
| `Blink/BApp.swift` | Modify | Create GhosttyApp at startup, pass via environment |
| `Blink/Views/Shell.swift` | Modify | Place TerminalView in content area |

---

## Chunk 1: Build Pipeline & Project Setup

### Task 1: Build GhosttyKit XCFramework

**Files:**
- Source: `~/Code/ghostty/`
- Output: `~/Code/ghostty/macos/GhosttyKit.xcframework/`

- [ ] **Step 1: Build the xcframework**

Run from the ghostty repo:
```bash
cd ~/Code/ghostty
zig build -Demit-xcframework=true -Dxcframework-target=native -Doptimize=ReleaseFast
```

This takes a few minutes. Output goes to `macos/GhosttyKit.xcframework/`.

- [ ] **Step 2: Verify the build output**

```bash
ls ~/Code/ghostty/macos/GhosttyKit.xcframework/
```

Expected: directory containing `Info.plist` and architecture-specific subdirectories with `libghostty.a` and `Headers/ghostty.h`.

- [ ] **Step 3: Copy xcframework into Blink project**

```bash
mkdir -p ~/Code/blink/Frameworks
cp -R ~/Code/ghostty/macos/GhosttyKit.xcframework ~/Code/blink/Frameworks/
```

- [ ] **Step 4: Verify the copy**

```bash
ls ~/Code/blink/Frameworks/GhosttyKit.xcframework/
```

- [ ] **Step 5: Commit**

```bash
cd ~/Code/blink
echo "Frameworks/" >> .gitignore
git add .gitignore
git commit -m "chore: ignore Frameworks directory (contains GhosttyKit xcframework)"
```

Note: The xcframework is large and built from source — don't commit it to git. Add to `.gitignore`.

---

### Task 2: Update project.yml for GhosttyKit

**Files:**
- Modify: `project.yml` (only the `Blink` target block — preserve `BTests`, `schemes`, and project-level `settings`)

- [ ] **Step 1: Add framework dependencies and linker flags to project.yml**

Update the `Blink` target to add GhosttyKit and system SDK dependencies. The full updated `project.yml`:

```yaml
name: Blink
settings:
  base:
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: 1
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    INFOPLIST_KEY_LSApplicationCategoryType: "public.app-category.developer-tools"
targets:
  Blink:
    type: application
    platform: macOS
    sources:
      - Blink
    resources:
      - path: Blink/Resources
        buildPhase: resources
    dependencies:
      - framework: Frameworks/GhosttyKit.xcframework
        embed: false
      - sdk: Metal.framework
      - sdk: CoreFoundation.framework
      - sdk: CoreGraphics.framework
      - sdk: CoreText.framework
      - sdk: CoreVideo.framework
      - sdk: QuartzCore.framework
      - sdk: IOSurface.framework
      - sdk: Carbon.framework
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.blink.app
        INFOPLIST_KEY_CFBundleDisplayName: Blink
        GENERATE_INFOPLIST_FILE: true
        PRODUCT_NAME: Blink
        OTHER_LDFLAGS:
          - "-lstdc++"
  BTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - BTests
    dependencies:
      - target: Blink
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.blink.app.tests
        GENERATE_INFOPLIST_FILE: true
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Blink.app/Contents/MacOS/Blink"
        BUNDLE_LOADER: "$(TEST_HOST)"
schemes:
  Blink:
    build:
      targets:
        Blink: all
        BTests: [test]
    test:
      targets:
        - BTests
```

- [ ] **Step 2: Regenerate Xcode project**

```bash
cd ~/Code/blink
xcodegen generate
```

Expected: `Generated project: Blink` or similar success message.

- [ ] **Step 3: Verify the project opens and builds (even with no GhosttyKit usage yet)**

```bash
cd ~/Code/blink
xcodebuild -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add project.yml
git commit -m "build: add GhosttyKit xcframework and system framework dependencies"
```

---

## Chunk 2: GhosttyApp Wrapper

### Task 3: Create GhosttyApp class

**Files:**
- Create: `Blink/Terminal/GhosttyApp.swift`

- [ ] **Step 1: Create the Terminal directory**

```bash
mkdir -p ~/Code/blink/Blink/Terminal
```

- [ ] **Step 2: Write GhosttyApp.swift**

```swift
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
        let configString = "background-opacity = 0\n"

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
```

- [ ] **Step 3: Verify build**

```bash
cd ~/Code/blink
xcodegen generate && xcodebuild -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add Blink/Terminal/GhosttyApp.swift
git commit -m "feat: add GhosttyApp wrapper for libghostty lifecycle"
```

---

## Chunk 3: Terminal Surface View (NSView)

### Task 4: Create TerminalSurfaceView

**Files:**
- Create: `Blink/Terminal/TerminalSurfaceView.swift`

This is the most complex file. It's an NSView subclass that:
- Hosts the Metal terminal surface
- Forwards keyboard and mouse input to libghostty
- Handles transparency (isOpaque = false, layer setup)
- Conforms to NSTextInputClient for proper text input

Key architectural note on keyboard input flow:
1. `keyDown` calls `interpretKeyEvents` which triggers `insertText` to accumulate text
2. The accumulated text is set on `ghostty_input_key_s.text` and sent via a single `ghostty_surface_key` call
3. `ghostty_surface_text` is NOT called from keyDown — it's only for direct text injection (paste)

- [ ] **Step 1: Write TerminalSurfaceView.swift**

```swift
import AppKit
import GhosttyKit

/// NSView subclass that hosts a single ghostty terminal surface.
/// Metal rendering, keyboard/mouse input, and transparency are handled here.
class TerminalSurfaceView: NSView, NSTextInputClient {

    private let ghosttyApp: GhosttyApp
    private var surface: ghostty_surface_t?
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?

    // MARK: - Init

    init(app: GhosttyApp) {
        self.ghosttyApp = app
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // Layer setup for transparency — Metal renders text at full opacity
        // independently from the background, so transparent bg + crisp text works.
        wantsLayer = true
        layer?.isOpaque = false

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
        cfg.scale_factor = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0

        surface = ghostty_surface_new(app, &cfg)
        if surface == nil {
            print("[TerminalSurfaceView] Failed to create surface")
            return
        }

        // Set initial size in framebuffer pixels (not points)
        let fbSize = convertToBacking(frame.size)
        ghostty_surface_set_size(surface, UInt32(fbSize.width), UInt32(fbSize.height))
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

    // MARK: - Cleanup

    deinit {
        if let surface { ghostty_surface_free(surface) }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd ~/Code/blink
xcodegen generate && xcodebuild -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add Blink/Terminal/TerminalSurfaceView.swift
git commit -m "feat: add TerminalSurfaceView NSView subclass for libghostty surface"
```

---

## Chunk 4: SwiftUI Wrapper & UI Integration

### Task 5: Create TerminalView (SwiftUI wrapper)

**Files:**
- Create: `Blink/Terminal/TerminalView.swift`

- [ ] **Step 1: Write TerminalView.swift**

```swift
import SwiftUI
import GhosttyKit

/// SwiftUI wrapper around TerminalSurfaceView.
struct TerminalView: NSViewRepresentable {
    let app: GhosttyApp

    func makeNSView(context: Context) -> TerminalSurfaceView {
        TerminalSurfaceView(app: app)
    }

    func updateNSView(_ nsView: TerminalSurfaceView, context: Context) {
        // No dynamic updates needed for PoC
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd ~/Code/blink
xcodegen generate && xcodebuild -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add Blink/Terminal/TerminalView.swift
git commit -m "feat: add TerminalView SwiftUI wrapper for NSViewRepresentable"
```

---

### Task 6: Wire GhosttyApp into BApp.swift and Shell.swift

**Files:**
- Modify: `Blink/BApp.swift`
- Modify: `Blink/Views/Shell.swift`

These two files must be updated together since Shell's interface changes.

- [ ] **Step 1: Update BApp.swift**

```swift
import SwiftUI
import GhosttyKit

@main
struct BApp: App {
    @State private var themeManager = ThemeManager()
    @State private var store = AppStore()
    @State private var ghosttyApp = GhosttyApp()

    var body: some Scene {
        WindowGroup {
            Shell(ghosttyApp: ghosttyApp)
                .environment(store)
                .environment(themeManager)
                .environment(\.theme, themeManager.activeTheme)
                .frame(
                    minWidth: Layout.windowMinWidth,
                    minHeight: Layout.windowMinHeight
                )
                .preferredColorScheme(.dark)
        }
        .defaultSize(
            width: Layout.windowDefaultWidth,
            height: Layout.windowDefaultHeight
        )
    }
}
```

- [ ] **Step 2: Update Shell.swift**

```swift
import SwiftUI
import GhosttyKit

struct Shell: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let ghosttyApp: GhosttyApp

    private var sidebarWidth: CGFloat {
        store.sidebarVisible ? Layout.sidebarWidth : Layout.sidebarCollapsedWidth
    }

    var body: some View {
        ZStack {
            // Wallpaper layer
            if let wallpaperId = store.backgroundImage {
                GeometryReader { geo in
                    wallpaperImage(for: wallpaperId)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(1.1)
                        .blur(radius: store.backgroundBlur)
                        .clipped()
                }
            }

            // Main layout — two columns with a single full-height divider
            HStack(spacing: 0) {
                // LEFT COLUMN: logo header + sidebar
                VStack(spacing: 0) {
                    // Logo header (same height as tab bar)
                    TabBarLogoArea()
                        .frame(height: Layout.tabBarHeight)

                    // Horizontal border under logo
                    theme.border.frame(height: 1)

                    // Sidebar content
                    SidebarView()
                }
                .frame(width: sidebarWidth)
                .background(
                    store.hasWallpaper
                        ? AnyShapeStyle(theme.bg.opacity(store.backgroundOpacity))
                        : AnyShapeStyle(theme.bg2)
                )

                // Full-height divider
                theme.border.frame(width: 1)

                // RIGHT COLUMN: tab bar + content + status line
                VStack(spacing: 0) {
                    // Tab bar (tabs only, no logo)
                    TabBarTabsArea()
                        .frame(height: Layout.tabBarHeight)

                    // Horizontal border under tabs
                    theme.border.frame(height: 1)

                    // Content area
                    ZStack {
                        if store.activeView == .settings {
                            if store.hasWallpaper {
                                theme.bg.opacity(store.backgroundOpacity)
                            } else {
                                theme.bg
                            }
                            SettingsPage()
                        } else if store.activeProjectId == nil {
                            if store.hasWallpaper {
                                theme.bg.opacity(store.backgroundOpacity)
                            } else {
                                theme.bg
                            }
                            StartScreen()
                        } else {
                            // Terminal — libghostty handles background transparency
                            // via background-opacity config. When no wallpaper is set,
                            // add a solid bg so the window isn't see-through.
                            if !store.hasWallpaper {
                                theme.bg
                            }
                            TerminalView(app: ghosttyApp)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Horizontal divider above status line
                    theme.border.frame(height: 1)

                    // Status line
                    StatusLine()
                        .frame(height: Layout.statusLineHeight)
                }
            }
            .background(store.hasWallpaper ? Color.clear : theme.bg)
            .font(Fonts.primary(size: 13))
        }
    }

    /// Load wallpaper image from bundle (preset) or file path (custom).
    private func wallpaperImage(for id: String) -> Image {
        if let preset = WallpaperPreset.find(id),
           let url = Bundle.main.url(forResource: preset.filename.replacingOccurrences(of: ".\(preset.filename.split(separator: ".").last ?? "")", with: ""),
                                     withExtension: String(preset.filename.split(separator: ".").last ?? "")),
           let nsImage = NSImage(contentsOf: url) {
            return Image(nsImage: nsImage)
        } else if !id.hasPrefix("preset:"), let nsImage = NSImage(contentsOfFile: id) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "photo")
    }
}
```

- [ ] **Step 3: Build and verify**

```bash
cd ~/Code/blink
xcodegen generate && xcodebuild -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Run the app and verify success criteria**

```bash
cd ~/Code/blink
open Blink.xcodeproj
```

Then in Xcode: Product → Run (Cmd+R)

**Verify all success criteria:**
1. App launches without crashing
2. A terminal appears in the content area with a shell prompt
3. You can type commands and see output
4. The terminal resizes when the window resizes
5. Keyboard input works (arrow keys, ctrl sequences, etc.)
6. Terminal background is transparent — wallpaper shows through, text is crisp

- [ ] **Step 5: Commit**

```bash
git add Blink/BApp.swift Blink/Views/Shell.swift Blink/Terminal/TerminalView.swift
git commit -m "feat: integrate libghostty terminal into content area with transparency"
```

---

## Troubleshooting

**Build fails with "No such module 'GhosttyKit'":**
- Verify `Frameworks/GhosttyKit.xcframework` exists
- Re-run `xcodegen generate`
- In Xcode: Product → Clean Build Folder, then rebuild

**`ghostty_init` fails or crashes:**
- Ensure Zig built the xcframework correctly (rebuild if needed)
- Check Console.app for crash logs

**Terminal doesn't appear (black/empty content area):**
- Check Console.app for `[GhosttyApp]` or `[TerminalSurfaceView]` error prints
- Verify `ghostty_app_new` returns non-nil (config or runtime callback issue)
- Verify `ghostty_surface_new` returns non-nil (surface config issue)

**Text is also transparent (the Krux problem):**
- Verify `background-opacity = 0` is in the config string (not window-level opacity)
- Verify `isOpaque` returns `false` on the NSView
- Verify `layer?.isOpaque = false` is set
- This should NOT happen with Metal rendering — if it does, it's a config issue

**Keyboard input doesn't work:**
- Verify `acceptsFirstResponder` returns `true`
- Click the terminal area to focus it
- Check that `insertText` is being called (add a debug print)

**Double characters appearing:**
- Ensure `keyDown` does NOT call `ghostty_surface_text` — text goes through `key_ev.text` only
- Check that `insertText` accumulates to `keyTextAccumulator` during keyDown

**Terminal renders at wrong resolution (blurry):**
- Check `viewDidChangeBackingProperties` is updating content scale
- Verify `convertToBacking` is used for size (framebuffer pixels, not points)

**Linker errors (undefined symbols):**
- Verify `project.yml` uses `sdk: Metal.framework` syntax (not `frameworks:`)
- Verify `-lstdc++` is in OTHER_LDFLAGS
- Re-run `xcodegen generate` and rebuild
