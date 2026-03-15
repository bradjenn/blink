# Settings Wiring — Theme System Overhaul + Opacity

## Goal

Unify Blink's theme system with Ghostty's terminal themes. One theme controls both the app UI chrome (sidebar, tab bar, status line) and the terminal colors. Replace the theme grid with a TUI-styled command-palette theme picker. Wire the opacity slider to Ghostty's `background-opacity` config.

## Architecture

Bundle all 464 Ghostty theme files as app resources. Parse theme files to extract terminal palette colors, then derive UI chrome colors from those same values. When a theme is selected, update both the SwiftUI UI and the Ghostty terminal config simultaneously.

## Design

### 1. Theme File Bundle

**Resource directory:** `Blink/Resources/Themes/`

- Copy all 464 Ghostty theme files from `~/Code/ghostty/zig-out/share/ghostty/themes/`
- Add 1 custom theme file: `Josean` (created from existing Josean theme colors — this is a synthetic Ghostty-format file optimized for both terminal rendering and UI derivation, since the Josean palette is custom to this project)
- Total: 465 theme files, each ~475 bytes (~220KB total)
- Theme file format is Ghostty's standard `key = value` format:
  ```
  palette = 0=#hex
  ...
  palette = 15=#hex
  background = #hex
  foreground = #hex
  cursor-color = #hex
  cursor-text = #hex
  selection-background = #hex
  selection-foreground = #hex
  ```

**10 favorites** (pinned at top of theme picker):
Josean, Dracula, Tokyo Night (→ `TokyoNight`), Catppuccin Mocha, Gruvbox Dark, Nord, One Dark (→ `Atom One Dark`), Solarized Dark (→ `Solarized Dark Patched`), Rose Pine (→ `Rose Pine`), Kanagawa (→ `Kanagawa Wave`)

### 2. Theme Parsing & UI Derivation

**File:** `Blink/Terminal/TerminalTheme.swift`

A `TerminalTheme` struct that parses a Ghostty theme file and holds:
- `name: String` — the theme name (filename)
- `background`, `foreground`, `cursorColor`, `cursorText`, `selectionBackground`, `selectionForeground` — as hex strings
- `palette: [String]` — 16 ANSI color hex strings (indices 0-15)

A function `deriveUITheme(from: TerminalTheme) -> Theme` maps terminal colors to UI tokens:

| UI Token | Source |
|---|---|
| `bg` | `background` |
| `bg2` | `background` darkened ~8% in HSB (most themes use a darker secondary bg) |
| `border` | `background` lightened ~12% in HSB |
| `text` | brighter of `foreground` and `palette[15]` (some themes use a dim foreground but bright white for UI) |
| `textMuted` | `text` at 60% opacity |
| `textDim` | `text` at 40% opacity |
| `accent` | `cursor-color` if it differs from `foreground`; otherwise `palette[4]` (blue) |
| `accent2` | `palette[6]` (cyan) |
| `danger` | `palette[1]` (red) |
| `green` | `palette[2]` (green) |
| `yellow` | `palette[3]` (yellow) |
| `magenta` | `palette[5]` (magenta) |

**Accent derivation rationale:** Using `cursor-color` as the primary accent works when the theme designer chose a distinctive cursor color (e.g. Catppuccin Mocha uses rosewater `#f5e0dc`, Nord uses bright white `#eceff4`). Many popular themes set `cursor-color == foreground`, so the fallback to `palette[4]` (blue) handles the majority — Dracula, Tokyo Night, One Dark, Rose Pine, Solarized, Kanagawa, Gruvbox all get blue as accent, which is a safe, visually coherent choice. The auto-derived accents won't perfectly match the hand-tuned originals (e.g. Kanagawa's handcrafted gold accent), but they'll be consistent and functional across all 465 themes.

**Brightness comparison:** "Brighter of foreground and palette[15]" is determined by comparing HSB brightness values.

**Parsed theme caching:** Parsed `TerminalTheme` instances are cached in a dictionary so scrolling through the theme picker doesn't re-parse files.

### 3. ThemeManager Overhaul

**File:** `Blink/Theme/ThemeManager.swift`

**Startup:**
- Scan `Blink/Resources/Themes/` bundle directory for all theme filenames → store as `[String]` (names only, no parsing)
- Parse only the active theme (stored theme name, default: `Josean`)
- Derive UI `Theme` from the parsed terminal theme

**Theme switching:**
- `setTheme(name: String)` — parse the theme file, derive UI theme, update environment
- Exposes `activeTerminalTheme: TerminalTheme` so callers can pass it to GhosttyApp
- Lazy parsing: only parse a theme file when it's selected or when color preview dots are needed in the picker

**Favorites list:** Hardcoded array of 10 theme names. Checked against available themes at startup.

### 4. GhosttyApp Config Rebuild

**File:** `Blink/Terminal/GhosttyApp.swift`

Add a method `updateConfig(terminalTheme: TerminalTheme, backgroundOpacity: Double)`:
1. Build a config string containing all theme color keys + `background-opacity = {value}`
2. Write to temp file, create new `ghostty_config_t` via `ghostty_config_new()`, load file via `ghostty_config_load_file()`, finalize, clean up temp file
3. Call `ghostty_app_update_config(app, newConfig)` — Ghostty copies what it needs internally
4. Free old `self.config` via `ghostty_config_free()`, store `newConfig` as `self.config`

**Config ownership:** `ghostty_app_update_config` does not take ownership of the config — it copies internally. The caller is responsible for the `ghostty_config_t` lifecycle. Verified against the Ghostty macOS app source where `newConfig` goes out of scope and is freed via Swift ARC after calling `ghostty_app_update_config`.

**Important:** The config string must include ALL non-default config keys Blink cares about (theme colors + background-opacity). If font settings are added later, they must be included in every `updateConfig()` call to avoid resetting to defaults.

This method is called when:
- User picks a new theme
- User adjusts the opacity slider

### 5. Theme Picker Modal

**File:** `Blink/Views/ThemePicker.swift`

A SwiftUI overlay with TUI aesthetic:

**Visual style:**
- Monospace font (JetBrains Mono) throughout
- Sharp corners, thin 1px border in `theme.border` color
- Semi-transparent backdrop dims the app (`Color.black.opacity(0.5)`)
- Panel: ~500pt wide, ~450pt tall, centered
- Background: `theme.bg`

**Layout (top to bottom):**
- Search input: monospace text field, auto-focused, placeholder "Search themes..."
- 1px divider
- Scrollable list:
  - "FAVORITES" header (small, muted text)
  - 10 favorite theme rows
  - "ALL" header
  - Remaining themes alphabetically (filtered by search)
- Each row: theme name (left-aligned) + 6 color dots (right-aligned) showing bg, fg, palette 1-4
- Active/selected row: subtle accent background highlight
- Current theme: small checkmark indicator

**Interaction:**
- Arrow keys navigate the list, Enter applies + dismisses, Escape dismisses
- Typing in search field filters both favorites and all themes instantly
- Clicking a row applies the theme immediately and dismisses
- Focus management: search field has focus, arrow keys move list selection via `onKeyPress` (macOS 14+) intercepting up/down before the text field consumes them

**Triggered from:**
- "Change Theme" button in AppearanceSettings (replaces the theme grid)
- (Later: keyboard shortcut)

### 6. AppearanceSettings Changes

**File:** `Blink/Views/Settings/AppearanceSettings.swift`

- Remove the theme grid (`LazyVGrid` with `ThemeCard`)
- Replace with a "Change Theme" button showing the current theme name
- Clicking it presents the `ThemePicker` modal
- Keep wallpaper section, opacity slider, blur slider as-is

**File:** `Blink/Views/Settings/ThemeCard.swift` — **Delete** (no longer needed)

### 7. AppStore Changes

**File:** `Blink/Store/AppStore.swift`

- Change `theme: String` to store the Ghostty theme filename (e.g. `"Dracula"`, `"Josean"`)
- Default value: `"Josean"`

**Note on persistence:** The existing `AppStore` has no persistence mechanism. Theme selection will persist for the app session but not across launches until persistence is added in a future step. This is acceptable for now.

### 8. Opacity Wiring

The opacity slider already exists and updates `store.backgroundOpacity`. The new behavior:
- When slider changes, call `ghosttyApp.updateConfig(terminalTheme: current, backgroundOpacity: newValue)`
- This hot-reloads the terminal's background opacity via `ghostty_app_update_config()`
- Sidebar/tab bar opacity continues to be driven by SwiftUI (unchanged)

### 9. Coordination: ThemeManager ↔ GhosttyApp

`ThemeManager` and `GhosttyApp` are separate `@State` objects in `BApp.swift`. They do not reference each other directly.

**Coordination happens at the call site** — the view that triggers a theme change (ThemePicker or AppearanceSettings) has access to both via SwiftUI environment/parameters and orchestrates the update:
1. Calls `themeManager.setTheme(name:)` → updates UI
2. Calls `ghosttyApp.updateConfig(terminalTheme: themeManager.activeTerminalTheme, backgroundOpacity: store.backgroundOpacity)` → updates terminal

Same pattern for opacity changes — the settings view calls both the store and ghosttyApp.

### 10. Data Flow

**User picks a theme:**
1. ThemePicker calls `themeManager.setTheme(name: "Dracula")`
2. ThemeManager parses `Dracula` theme file → `TerminalTheme`
3. Derives UI `Theme` from terminal palette
4. Updates SwiftUI environment → all chrome re-renders
5. ThemePicker calls `ghosttyApp.updateConfig(terminalTheme, store.backgroundOpacity)`
6. Terminal re-renders with new colors

**User adjusts opacity slider:**
1. Slider → `store.setBackgroundOpacity(0.8)`
2. SwiftUI sidebar/chrome updates (existing behavior)
3. Settings view calls `ghosttyApp.updateConfig(currentTheme, 0.8)`
4. Terminal background opacity updates

## Files Summary

| File | Action | Purpose |
|---|---|---|
| `Blink/Resources/Themes/` | Create | 465 Ghostty theme files (464 + Josean) |
| `Blink/Terminal/TerminalTheme.swift` | Create | Parse theme files, derive UI Theme, cache parsed themes |
| `Blink/Terminal/GhosttyApp.swift` | Modify | Add `updateConfig()` for hot-reload |
| `Blink/Theme/Theme.swift` | Modify | Remove hardcoded presets, keep struct with same tokens |
| `Blink/Theme/ThemeManager.swift` | Modify | Load from theme files, lazy parsing, expose activeTerminalTheme |
| `Blink/Views/ThemePicker.swift` | Create | Command-palette theme picker modal |
| `Blink/Views/Settings/AppearanceSettings.swift` | Modify | Replace grid with "Change Theme" button |
| `Blink/Views/Settings/ThemeCard.swift` | Delete | No longer needed |
| `Blink/Store/AppStore.swift` | Modify | Theme name as string, default "Josean" |

## What Gets Removed

- 11 hardcoded `Theme` presets in Theme.swift (replaced by runtime derivation)
- Theme grid in AppearanceSettings
- `ThemeCard.swift`
- Cyberpunk theme (per user request)

## Success Criteria

1. Selecting a theme in the picker updates both the app chrome and terminal colors instantly
2. All 465 themes are searchable and selectable
3. 10 favorites appear pinned at the top
4. Adjusting the opacity slider updates the terminal's background opacity in real-time
5. App startup is instant (lazy theme parsing)
6. Theme picker feels like a TUI — monospace, sharp, keyboard-navigable
