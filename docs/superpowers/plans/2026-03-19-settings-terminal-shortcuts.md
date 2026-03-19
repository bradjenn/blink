# Settings: Terminal & Keyboard Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable the Terminal and Keyboard Shortcuts settings tabs with four terminal settings (font family, font size, cursor style, shell) and a read-only keyboard shortcuts reference.

**Architecture:** New properties on AppStore persisted via UserDefaults. Font/size/cursor feed into `TerminalTheme.toConfigString()` as parameters and hot-reload via `GhosttyApp.updateConfig()`. Shell is read at surface creation time only. Keyboard shortcuts are a static data model rendered as a grouped list.

**Tech Stack:** SwiftUI, AppKit (NSFontManager for font enumeration), Ghostty config API

---

### Task 1: Add CursorStyle enum

**Files:**
- Create: `Blink/Models/CursorStyle.swift`

- [ ] **Step 1: Create the enum**

```swift
import Foundation

enum CursorStyle: String, CaseIterable, Codable {
    case block = "block"
    case bar = "bar"
    case underline = "underline"

    var displayName: String {
        switch self {
        case .block: "Block"
        case .bar: "Bar"
        case .underline: "Underline"
        }
    }
}
```

- [ ] **Step 2: Commit**

```
git add Blink/Models/CursorStyle.swift
git commit -m "feat: add CursorStyle enum for terminal settings"
```

---

### Task 2: Add terminal settings to AppStore

**Files:**
- Modify: `Blink/Store/AppStore.swift`

- [ ] **Step 1: Add storage keys** (after line 20, inside `StorageKeys`)

```swift
static let fontFamily = "blink.fontFamily"
static let fontSize = "blink.fontSize"
static let cursorStyle = "blink.cursorStyle"
static let shell = "blink.shell"
```

- [ ] **Step 2: Add properties** (after the `sidebarVisible` property, ~line 79)

```swift
var fontFamily: String {
    didSet { UserDefaults.standard.set(fontFamily, forKey: StorageKeys.fontFamily) }
}
var fontSize: Double {
    didSet { UserDefaults.standard.set(fontSize, forKey: StorageKeys.fontSize) }
}
var cursorStyle: CursorStyle {
    didSet { UserDefaults.standard.set(cursorStyle.rawValue, forKey: StorageKeys.cursorStyle) }
}
var shell: String {
    didSet { UserDefaults.standard.set(shell, forKey: StorageKeys.shell) }
}
```

- [ ] **Step 3: Initialize from UserDefaults** (in `init()`, after `self.sidebarVisible` line)

```swift
self.fontFamily = defaults.string(forKey: StorageKeys.fontFamily) ?? "MesloLGS Nerd Font Mono"
self.fontSize = defaults.object(forKey: StorageKeys.fontSize) != nil
    ? defaults.double(forKey: StorageKeys.fontSize) : 19
self.cursorStyle = CursorStyle(rawValue: defaults.string(forKey: StorageKeys.cursorStyle) ?? "") ?? .block
self.shell = defaults.string(forKey: StorageKeys.shell)
    ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
```

- [ ] **Step 4: Add a computed default shell property** (near the other computed properties)

```swift
static var defaultShell: String {
    ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
}
```

- [ ] **Step 5: Build to verify** — `xcodebuild -scheme Blink -configuration Debug build`

- [ ] **Step 6: Commit**

```
git add Blink/Store/AppStore.swift
git commit -m "feat: add terminal settings properties to AppStore"
```

---

### Task 3: Wire terminal settings into Ghostty config

**Files:**
- Modify: `Blink/Terminal/TerminalTheme.swift` — `toConfigString()` method (line 88)
- Modify: `Blink/Terminal/GhosttyApp.swift` — `updateConfig()` (line 205), `init()` (line 80)
- Modify: `Blink/Terminal/TerminalSurfaceView.swift` — `createSurface()` shell resolution (line 123)

- [ ] **Step 1: Update `toConfigString()` signature to accept terminal settings**

Replace the current method (line 88-108 of TerminalTheme.swift):

```swift
func toConfigString(
    backgroundOpacity: Double = 0,
    fontFamily: String = "MesloLGS Nerd Font Mono",
    fontSize: Double = 19,
    cursorStyle: CursorStyle = .block
) -> String {
    var lines = [String]()
    for (i, color) in palette.enumerated() {
        lines.append("palette = \(i)=\(color)")
    }
    lines.append("background = \(background)")
    lines.append("foreground = \(foreground)")
    lines.append("cursor-color = \(cursorColor)")
    lines.append("cursor-text = \(cursorText)")
    lines.append("selection-background = \(selectionBackground)")
    lines.append("selection-foreground = \(selectionForeground)")
    lines.append("background-opacity = 0")
    lines.append("font-family = \(fontFamily)")
    lines.append("font-size = \(Int(fontSize))")
    lines.append("cursor-shape = \(cursorStyle.rawValue)")
    lines.append("window-padding-x = 16")
    lines.append("window-padding-y = 10")
    lines.append("audible-bell = false")
    lines.append("visual-bell = false")
    return lines.joined(separator: "\n") + "\n"
}
```

- [ ] **Step 2: Update `GhosttyApp.updateConfig()` to pass terminal settings**

Replace the method signature and body (line 205-223 of GhosttyApp.swift):

```swift
func updateConfig(terminalTheme: TerminalTheme, backgroundOpacity: Double, fontFamily: String, fontSize: Double, cursorStyle: CursorStyle) {
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

    if let oldConfig = config {
        ghostty_config_free(oldConfig)
    }
    config = newCfg
    activeConfigKey = configString
}
```

- [ ] **Step 3: Update `GhosttyApp.init()` to read terminal settings for initial config** (line 69-84)

After the existing defaults reads, add:

```swift
let fontFamily = defaults.string(forKey: "blink.fontFamily") ?? "MesloLGS Nerd Font Mono"
let fontSize = defaults.object(forKey: "blink.fontSize") != nil
    ? defaults.double(forKey: "blink.fontSize") : 19.0
let cursorStyle = CursorStyle(rawValue: defaults.string(forKey: "blink.cursorStyle") ?? "") ?? .block
```

And update the `toConfigString` call:

```swift
configString = defaultTheme.toConfigString(
    backgroundOpacity: opacity,
    fontFamily: fontFamily,
    fontSize: fontSize,
    cursorStyle: cursorStyle
)
```

- [ ] **Step 4: Update `TerminalSurfaceView.createSurface()` to read shell from AppStore**

In `TerminalSurfaceView.swift` line 123, replace:

```swift
let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
```

With:

```swift
let shell = UserDefaults.standard.string(forKey: "blink.shell")
    ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
```

- [ ] **Step 5: Update all `updateConfig()` call sites in AppearanceSettings.swift**

In `AppearanceSettings.swift`, update both calls to `ghosttyApp.updateConfig()` (lines 122-125 and 192) to pass the new parameters:

```swift
ghosttyApp.updateConfig(
    terminalTheme: termTheme,
    backgroundOpacity: effectiveOpacity,
    fontFamily: store.fontFamily,
    fontSize: store.fontSize,
    cursorStyle: store.cursorStyle
)
```

- [ ] **Step 6: Build to verify** — `xcodebuild -scheme Blink -configuration Debug build`

- [ ] **Step 7: Commit**

```
git add Blink/Terminal/TerminalTheme.swift Blink/Terminal/GhosttyApp.swift Blink/Terminal/TerminalSurfaceView.swift Blink/Views/Settings/AppearanceSettings.swift
git commit -m "feat: wire terminal settings into Ghostty config pipeline"
```

---

### Task 4: Create TerminalSettings view

**Files:**
- Create: `Blink/Views/Settings/TerminalSettings.swift`

- [ ] **Step 1: Create the view**

Follow the AppearanceSettings pattern: ScrollView > VStack with section headers. Four settings:

1. **Font Family** — `Picker` with monospace system fonts. Query via `NSFontManager.shared.availableFontFamilies` filtered to monospace. Bundled MesloLGS pinned at top.
2. **Font Size** — `Stepper` with 10-32 range, display current value.
3. **Cursor Style** — `Picker` with `.segmented` style showing Block/Bar/Underline.
4. **Shell** — `TextField` with current path + "Reset" button to revert to `$SHELL`.

Each setting change for font/size/cursor triggers `ghosttyApp.updateConfig()` via an `onChange` modifier (same pattern as AppearanceSettings opacity slider). Shell changes just persist — no hot-reload needed.

```swift
import SwiftUI
import AppKit

struct TerminalSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    let ghosttyApp: GhosttyApp

    @State private var monospaceFonts: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Terminal")
                    .font(Fonts.primary(size: 18, weight: .bold))
                    .foregroundStyle(theme.text)

                fontFamilySection
                fontSizeSection
                cursorStyleSection
                shellSection

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .task { monospaceFonts = Self.loadMonospaceFonts() }
    }

    private var fontFamilySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Font family")
                .font(Fonts.primary(size: 14, weight: .medium))
                .foregroundStyle(theme.text)
            Text("Monospace font used in the terminal")
                .font(Fonts.primary(size: 12))
                .foregroundStyle(theme.textMuted)

            Picker("", selection: Binding(
                get: { store.fontFamily },
                set: { newValue in
                    store.fontFamily = newValue
                    updateTerminalConfig()
                }
            )) {
                Text("MesloLGS Nerd Font Mono").tag("MesloLGS Nerd Font Mono")
                if !monospaceFonts.isEmpty {
                    Divider()
                    ForEach(monospaceFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: 300)
        }
    }

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Font size")
                .font(Fonts.primary(size: 14, weight: .medium))
                .foregroundStyle(theme.text)
            Text("Size in points for terminal text")
                .font(Fonts.primary(size: 12))
                .foregroundStyle(theme.textMuted)

            HStack(spacing: 12) {
                @Bindable var store = store
                Stepper(
                    "\(Int(store.fontSize))pt",
                    value: $store.fontSize,
                    in: 10...32,
                    step: 1
                )
                .font(Fonts.primary(size: 13))
                .foregroundStyle(theme.text)
                .onChange(of: store.fontSize) {
                    updateTerminalConfig()
                }
            }
        }
    }

    private var cursorStyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cursor style")
                .font(Fonts.primary(size: 14, weight: .medium))
                .foregroundStyle(theme.text)
            Text("Shape of the terminal cursor")
                .font(Fonts.primary(size: 12))
                .foregroundStyle(theme.textMuted)

            Picker("", selection: Binding(
                get: { store.cursorStyle },
                set: { newValue in
                    store.cursorStyle = newValue
                    updateTerminalConfig()
                }
            )) {
                ForEach(CursorStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
        }
    }

    private var shellSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shell")
                .font(Fonts.primary(size: 14, weight: .medium))
                .foregroundStyle(theme.text)
            Text("Program to run in new terminal tabs (changes apply to new tabs)")
                .font(Fonts.primary(size: 12))
                .foregroundStyle(theme.textMuted)

            HStack(spacing: 8) {
                @Bindable var store = store
                TextField("Shell path", text: $store.shell)
                    .textFieldStyle(.roundedBorder)
                    .font(Fonts.mono(size: 13))
                    .frame(maxWidth: 300)

                if store.shell != AppStore.defaultShell {
                    Button("Reset") {
                        store.shell = AppStore.defaultShell
                    }
                    .font(Fonts.primary(size: 12))
                    .foregroundStyle(theme.accent)
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }
        }
    }

    private func updateTerminalConfig() {
        if let termTheme = themeManager.activeTerminalTheme {
            let effectiveOpacity = store.hasWallpaper ? store.backgroundOpacity : 1.0
            ghosttyApp.updateConfig(
                terminalTheme: termTheme,
                backgroundOpacity: effectiveOpacity,
                fontFamily: store.fontFamily,
                fontSize: store.fontSize,
                cursorStyle: store.cursorStyle
            )
        }
    }

    private static func loadMonospaceFonts() -> [String] {
        let manager = NSFontManager.shared
        let allFamilies = manager.availableFontFamilies
        return allFamilies.filter { family in
            guard let members = manager.availableMembers(ofFontFamily: family),
                  let first = members.first,
                  let fontName = first[0] as? String,
                  let font = NSFont(name: fontName, size: 13) else { return false }
            return font.isFixedPitch
        }
        .filter { $0 != "MesloLGS Nerd Font Mono" }
        .sorted()
    }
}
```

- [ ] **Step 2: Check for `Fonts.mono` helper** — if it doesn't exist, use `Font.system(size: 13, design: .monospaced)` instead.

- [ ] **Step 3: Build to verify** — `xcodebuild -scheme Blink -configuration Debug build`

- [ ] **Step 4: Commit**

```
git add Blink/Views/Settings/TerminalSettings.swift
git commit -m "feat: add TerminalSettings view with font, cursor, and shell controls"
```

---

### Task 5: Create KeyboardShortcutsSettings view

**Files:**
- Create: `Blink/Views/Settings/KeyboardShortcutsSettings.swift`

- [ ] **Step 1: Create the view with static shortcut data**

```swift
import SwiftUI

private struct ShortcutEntry: Identifiable {
    let id = UUID()
    let action: String
    let keys: String
}

private struct ShortcutCategory: Identifiable {
    let id = UUID()
    let name: String
    let shortcuts: [ShortcutEntry]
}

private let shortcutCategories: [ShortcutCategory] = [
    ShortcutCategory(name: "Navigation", shortcuts: [
        ShortcutEntry(action: "Focus Left", keys: "⌘H"),
        ShortcutEntry(action: "Focus Right", keys: "⌘L"),
        ShortcutEntry(action: "Focus Down", keys: "⌘J"),
        ShortcutEntry(action: "Focus Up", keys: "⌘K"),
    ]),
    ShortcutCategory(name: "Windows", shortcuts: [
        ShortcutEntry(action: "New Window", keys: "⌘T"),
        ShortcutEntry(action: "Close Window", keys: "⌘W"),
        ShortcutEntry(action: "Window 1–9", keys: "⌘1–9"),
    ]),
    ShortcutCategory(name: "Columns", shortcuts: [
        ShortcutEntry(action: "Move Window Left", keys: "⇧⌘H"),
        ShortcutEntry(action: "Move Window Right", keys: "⇧⌘L"),
        ShortcutEntry(action: "Absorb from Left", keys: "⇧⌘J"),
        ShortcutEntry(action: "Absorb from Right", keys: "⇧⌘K"),
        ShortcutEntry(action: "Expel Pane", keys: "⇧⌘E"),
        ShortcutEntry(action: "Resize Column", keys: "⌘R"),
        ShortcutEntry(action: "Maximize Column", keys: "⌘F"),
    ]),
    ShortcutCategory(name: "Workspace", shortcuts: [
        ShortcutEntry(action: "Toggle Sidebar", keys: "⌘B"),
        ShortcutEntry(action: "Overview", keys: "⌘O"),
        ShortcutEntry(action: "Open Git", keys: "⌘G"),
    ]),
    ShortcutCategory(name: "App", shortcuts: [
        ShortcutEntry(action: "Settings", keys: "⌘,"),
        ShortcutEntry(action: "Switch Project", keys: "⌘P"),
        ShortcutEntry(action: "Switch Theme", keys: "⇧⌘T"),
    ]),
]

struct KeyboardShortcutsSettings: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Keyboard Shortcuts")
                    .font(Fonts.primary(size: 18, weight: .bold))
                    .foregroundStyle(theme.text)

                ForEach(shortcutCategories) { category in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category.name)
                            .font(Fonts.primary(size: 14, weight: .medium))
                            .foregroundStyle(theme.text)
                            .padding(.bottom, 4)

                        ForEach(category.shortcuts) { shortcut in
                            HStack {
                                Text(shortcut.action)
                                    .font(Fonts.primary(size: 13))
                                    .foregroundStyle(theme.textMuted)
                                Spacer()
                                KeyCapBadge(keys: shortcut.keys)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
}

private struct KeyCapBadge: View {
    @Environment(\.theme) private var theme
    let keys: String

    var body: some View {
        Text(keys)
            .font(Fonts.mono(size: 12))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }
}
```

Note: If `Fonts.mono` doesn't exist, use `.font(.system(size: 12, design: .monospaced))` instead.

- [ ] **Step 2: Build to verify** — `xcodebuild -scheme Blink -configuration Debug build`

- [ ] **Step 3: Commit**

```
git add Blink/Views/Settings/KeyboardShortcutsSettings.swift
git commit -m "feat: add read-only keyboard shortcuts reference view"
```

---

### Task 6: Wire tabs into SettingsPage and enable navigation

**Files:**
- Modify: `Blink/Views/SettingsPage.swift`

- [ ] **Step 1: Remove the disabled guard**

In SettingsPage.swift, replace line 43:

```swift
let isDisabled = tab != .appearance
```

With:

```swift
let isDisabled = false
```

- [ ] **Step 2: Wire the new views into the tab switch** (lines 70-85)

Replace the terminal and keyboard shortcuts cases:

```swift
case .terminal:
    TerminalSettings(ghosttyApp: ghosttyApp)
case .keyboardShortcuts:
    KeyboardShortcutsSettings()
```

- [ ] **Step 3: Build to verify** — `xcodebuild -scheme Blink -configuration Debug build`

- [ ] **Step 4: Test manually** — Run the app, open settings, verify all three tabs work

- [ ] **Step 5: Commit**

```
git add Blink/Views/SettingsPage.swift
git commit -m "feat: enable Terminal and Keyboard Shortcuts settings tabs"
```
