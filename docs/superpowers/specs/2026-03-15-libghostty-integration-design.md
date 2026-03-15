# libghostty Integration — Proof of Concept

## Goal

Get a single working terminal rendering in Blink's content area using libghostty (the Ghostty terminal emulator's core library). Type commands, see output. Prove the concept works end-to-end.

## Approach

Full GhosttyKit embedding via xcframework. Build the C library from Bradley's Ghostty fork (`~/Code/ghostty`), wrap it in Swift, and render a terminal surface in the existing content area using Metal.

## Architecture

Four components, minimal footprint:

### 1. Build Pipeline

- Build `GhosttyKit.xcframework` from `~/Code/ghostty` using: `zig build -Demit-xcframework=true -Dxcframework-target=native -Doptimize=ReleaseFast` (use `native` for faster PoC builds — only builds for your machine's architecture)
- Output: `~/Code/ghostty/macos/GhosttyKit.xcframework/` (static library + C headers + module map)
- Copy into `~/Code/blink/Frameworks/GhosttyKit.xcframework`
- Update `project.yml` to reference the framework and link system dependencies:
  - **Frameworks:** `Metal`, `CoreFoundation`, `CoreGraphics`, `CoreText`, `CoreVideo`, `QuartzCore`, `IOSurface`, `Carbon`
  - **Linker flags:** `-lstdc++`
- After this, `import GhosttyKit` is available in Swift

### 2. GhosttyApp (App Handle Wrapper)

**File:** `Blink/Terminal/GhosttyApp.swift`

A Swift class wrapping the `ghostty_app_t` lifecycle:

- Creates `ghostty_config_t` programmatically — does NOT load Ghostty's config files (`~/.config/ghostty/config`). Blink owns all terminal settings. Calls `ghostty_config_new()`, sets values via the config API, then `ghostty_config_finalize()`.
- **Critical config for PoC:** `background-opacity` set to match Blink's wallpaper opacity (enables transparent background with crisp text rendering — this is the core value proposition)
- Builds `ghostty_runtime_config_s` with C function pointer callbacks (wakeup, action handler, clipboard, close surface)
- Calls `ghostty_app_new(&runtime_cfg, config)` to create the app handle
- **Wakeup callback drives the render loop:** The wakeup callback is called from any thread and must dispatch `ghostty_app_tick()` onto the main thread via `DispatchQueue.main.async`. There is no timer — the wakeup callback is the sole driver of updates.
- Exposes a method to create new surfaces
- **Action callback:** Returns `false` for all actions in the PoC (stub). Some terminal features like link clicking won't work until actions are implemented.

**Callback bridging:** Uses `Unmanaged<GhosttyApp>` as `userdata` to bridge from C function pointers back to Swift. Same pattern as the Ghostty macOS app.

**Lifecycle:** Created once at app launch in `BApp.swift`, lives for the entire session.

### 3. TerminalSurfaceView (NSView + SwiftUI Wrapper)

**Files:**
- `Blink/Terminal/TerminalSurfaceView.swift` — `NSView` subclass
- `Blink/Terminal/TerminalView.swift` — `NSViewRepresentable` SwiftUI wrapper

**NSView subclass:**
- On creation, calls `ghostty_surface_new(app, &surfaceConfig)` with a properly configured `ghostty_surface_config_s`:
  - `platform_tag` = `GHOSTTY_PLATFORM_MACOS`
  - `platform` = union with `macos` variant containing `ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque())`
  - `userdata` = `Unmanaged.passUnretained(self).toOpaque()`
  - `scale_factor` = `NSScreen.main!.backingScaleFactor`
- libghostty's Metal renderer draws directly onto this view
- **Transparency setup:** `wantsLayer = true`, `layer?.isOpaque = false`, and the view itself must report `isOpaque = false`. This allows the transparent terminal background (set via `background-opacity` config) to composite over Blink's wallpaper ZStack layer. Metal renders text glyphs at full opacity independently — no text transparency.
- **Size must be in framebuffer pixels** (not points): call `self.convertToBacking(size)` before passing to `ghostty_surface_set_size()`
- Sets content scale via `ghostty_surface_set_content_scale()`
- Overrides `keyDown`, `keyUp`, `flagsChanged` → `ghostty_surface_key()`
- **Must conform to `NSTextInputClient`** for proper text input handling — at minimum implement `insertText` routing to `ghostty_surface_text()`. Without this, IME and composed characters won't work.
- Overrides `mouseDown`, `mouseMoved`, `scrollWheel` → `ghostty_surface_mouse_*()` functions
- Overrides `layout()`/`setFrameSize()` to update libghostty on resize
- Accepts first responder for keyboard input

**SwiftUI wrapper:**
- `NSViewRepresentable` creating and returning the `TerminalSurfaceView`
- Takes a `GhosttyApp` reference
- Implements `makeNSView` and `updateNSView`

### 4. UI Integration

**`BApp.swift`:** Create `GhosttyApp` at startup, pass via environment or parameter.

**`Shell.swift`:** Place `TerminalView(app: ghosttyApp)` in the content area (right column, between tab bar and status line). Keep `StartScreen` when no project is selected. Keep settings overlay as-is.

**`AppStore.swift`:** No changes.

## Explicitly Out of Scope

- Per-tab surface management (all tabs share one terminal for now)
- Full theme color passthrough to libghostty (only background-opacity is wired up for now)
- Custom font configuration
- Splits
- Terminal lifecycle tied to tab open/close
- Working directory per project

## Success Criteria

1. App launches without crashing
2. A terminal appears in the content area with a shell prompt
3. You can type commands and see output
4. The terminal resizes when the window resizes
5. Keyboard input works (arrow keys, ctrl sequences, etc.)
6. **Terminal background is transparent** — wallpaper/background shows through while text remains fully opaque and crisp

## Dependencies

- Zig 0.15.2+ (installed via `brew install zig`)
- Ghostty fork at `~/Code/ghostty`
- System frameworks: Metal, CoreFoundation, CoreGraphics, CoreText, CoreVideo, QuartzCore, IOSurface, Carbon
- Linker flag: `-lstdc++`

## Key Reference

- Ghostty macOS app source: `~/Code/ghostty/macos/Sources/`
- C API header: `~/Code/ghostty/include/ghostty.h`
- Ghostty's own SwiftUI surface wrapper: `macos/Sources/Ghostty/Surface View/SurfaceView.swift`
- Ghostty's NSView subclass: `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`
- Ghostty's app wrapper: `macos/Sources/Ghostty/Ghostty.App.swift`
