# Settings: Terminal & Keyboard Shortcuts Tabs

## Context

The settings page has three tabs but only Appearance works. Terminal and Keyboard Shortcuts are disabled stubs. This spec adds both.

## Terminal Settings

Four settings persisted via UserDefaults through AppStore, hot-reloaded via `GhosttyApp.updateConfig()`.

### Settings

| Setting | Control | Range | Default | Storage Key |
|---------|---------|-------|---------|-------------|
| Font Family | Dropdown picker | Monospace system fonts + bundled MesloLGS | MesloLGS Nerd Font Mono | `blink.fontFamily` |
| Font Size | Stepper (+/-) | 10–32pt | 19 | `blink.fontSize` |
| Cursor Style | Segmented picker | Block / Bar / Underline | Block | `blink.cursorStyle` |
| Shell | Text field + Reset button | Any valid path | `$SHELL` | `blink.shell` |

### Layout

Matches AppearanceSettings style: section headers with label-left / control-right rows. Scrollable if content overflows.

### Hot-reload

All four settings feed into `TerminalTheme.toConfigString()` which already generates the Ghostty config block. The new properties get interpolated into that string. `GhosttyApp.updateConfig()` pushes changes to all active surfaces without restart.

### Cursor style enum

```swift
enum CursorStyle: String, CaseIterable {
    case block = "block"
    case bar = "bar"
    case underline = "underline"
}
```

The raw values match Ghostty's `cursor-shape` config key.

### Font family picker

Query monospace system fonts via `NSFontManager.shared.availableFontFamilies` filtered to monospace traits. Prepend the bundled MesloLGS Nerd Font Mono at the top. Display each option in its own font face for preview.

## Keyboard Shortcuts (Read-only)

A reference table displaying all current shortcuts. No rebinding — just discovery.

### Categories

| Category | Shortcuts |
|----------|-----------|
| **Navigation** | Focus Left (Cmd+H), Focus Right (Cmd+L), Focus Down (Cmd+J), Focus Up (Cmd+K) |
| **Windows** | New Window (Cmd+T), Close Window (Cmd+W), Window 1-9 (Cmd+1-9) |
| **Columns** | Move Left (Cmd+Shift+H), Move Right (Cmd+Shift+L), Absorb Left (Cmd+Shift+J), Absorb Right (Cmd+Shift+K), Expel Pane (Cmd+Shift+E), Resize (Cmd+R), Maximize (Cmd+F) |
| **Workspace** | Toggle Sidebar (Cmd+B), Overview (Cmd+O), Open Git (Cmd+G) |
| **App** | Settings (Cmd+,), Switch Project (Cmd+P), Switch Theme (Cmd+Shift+T) |

### Layout

Grouped by category with section headers. Each row: action name (left) and key combo badge (right). Key badges styled as keycap-like rounded rects with monospace text, matching the app's visual language.

### Data model

Static array of shortcut definitions — no persistence needed:

```swift
struct KeyboardShortcut {
    let action: String
    let keys: String      // e.g. "Cmd+H"
    let category: String
}
```

## Enabling the tabs

Remove the `isDisabled` guard in SettingsPage.swift so all three tabs are navigable.

## Files to create/modify

| File | Action |
|------|--------|
| `Blink/Store/AppStore.swift` | Add fontFamily, fontSize, cursorStyle, shell properties + StorageKeys + defaults |
| `Blink/Terminal/TerminalTheme.swift` | Read new properties in `toConfigString()` |
| `Blink/Views/Settings/TerminalSettings.swift` | New file — terminal settings panel |
| `Blink/Views/Settings/KeyboardShortcutsSettings.swift` | New file — read-only shortcuts reference |
| `Blink/Views/SettingsPage.swift` | Remove disabled guard, wire new views |
| `Blink/Models/CursorStyle.swift` | New file — CursorStyle enum |
