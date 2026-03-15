# Settings Wiring — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify Blink's theme system with 465 Ghostty themes, add a TUI-styled theme picker, and wire the opacity slider to the terminal.

**Architecture:** Bundle Ghostty theme files as resources, parse them into a `TerminalTheme` struct, derive UI `Theme` from palette colors, hot-reload terminal via `ghostty_app_update_config()`.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, GhosttyKit, XcodeGen

**Spec:** `docs/superpowers/specs/2026-03-15-settings-wiring-design.md`

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `Blink/Resources/Themes/` | Create | 465 Ghostty theme files |
| `Blink/Terminal/TerminalTheme.swift` | Create | Parse theme files, derive UI Theme |
| `Blink/Terminal/GhosttyApp.swift` | Modify | Add `updateConfig()` method |
| `Blink/Theme/Theme.swift` | Modify | Remove hardcoded presets, keep struct + derivation default |
| `Blink/Theme/ThemeManager.swift` | Modify | Load from theme files, lazy parsing |
| `Blink/Views/ThemePicker.swift` | Create | Command-palette theme picker modal |
| `Blink/Views/Settings/AppearanceSettings.swift` | Modify | Replace grid with "Change Theme" button |
| `Blink/Views/Settings/ThemeCard.swift` | Delete | No longer needed |
| `Blink/Store/AppStore.swift` | Modify | Default theme = "Josean" |
| `Blink/BApp.swift` | Modify | Pass ghosttyApp to ThemePicker |

---

## Chunk 1: Theme Files & Parser

### Task 1: Bundle Ghostty theme files

- [ ] **Step 1: Copy all 464 Ghostty themes into the project**

```bash
cp -R ~/Code/ghostty/zig-out/share/ghostty/themes/ ~/Code/blink/Blink/Resources/Themes/
```

- [ ] **Step 2: Create custom Josean theme file**

Create `Blink/Resources/Themes/Josean` with terminal palette colors derived from the existing Josean theme in Theme.swift:

```
palette = 0=#01101c
palette = 1=#e52e2e
palette = 2=#44ffb1
palette = 3=#ffe073
palette = 4=#0fc5ed
palette = 5=#a277ff
palette = 6=#47ff9c
palette = 7=#cbe0f0
palette = 8=#033259
palette = 9=#e52e2e
palette = 10=#44ffb1
palette = 11=#ffe073
palette = 12=#0fc5ed
palette = 13=#a277ff
palette = 14=#47ff9c
palette = 15=#cbe0f0
background = #011423
foreground = #cbe0f0
cursor-color = #47ff9c
cursor-text = #011423
selection-background = #033259
selection-foreground = #cbe0f0
```

- [ ] **Step 3: Verify theme count**

```bash
ls ~/Code/blink/Blink/Resources/Themes/ | wc -l
```

Expected: 465

- [ ] **Step 4: Update project.yml resources to include Themes directory**

The existing `resources` entry covers `Blink/Resources` so themes are already included. Verify by regenerating:

```bash
cd ~/Code/blink && xcodegen generate
```

- [ ] **Step 5: Commit**

```bash
git add Blink/Resources/Themes/
git commit -m "chore: bundle 465 Ghostty theme files as resources"
```

Note: This is a large commit (~465 files, ~220KB total).

---

### Task 2: Create TerminalTheme parser

**Files:**
- Create: `Blink/Terminal/TerminalTheme.swift`

- [ ] **Step 1: Write TerminalTheme.swift**

```swift
import SwiftUI

/// Parsed representation of a Ghostty theme file.
struct TerminalTheme {
    let name: String
    let background: String
    let foreground: String
    let cursorColor: String
    let cursorText: String
    let selectionBackground: String
    let selectionForeground: String
    let palette: [String] // 16 ANSI colors (indices 0-15)

    /// Parse a Ghostty theme file from its contents.
    static func parse(name: String, contents: String) -> TerminalTheme? {
        var bg = "#000000"
        var fg = "#ffffff"
        var cursor = "#ffffff"
        var cursorTxt = "#000000"
        var selBg = "#444444"
        var selFg = "#ffffff"
        var pal = [String](repeating: "#000000", count: 16)

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            // Split on first "="
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)

            switch key {
            case "background":
                bg = value
            case "foreground":
                fg = value
            case "cursor-color":
                cursor = value
            case "cursor-text":
                cursorTxt = value
            case "selection-background":
                selBg = value
            case "selection-foreground":
                selFg = value
            default:
                // Handle "palette = N=#hex"
                if key.hasPrefix("palette") {
                    // Value is "N=#hex" — the key is literally "palette"
                    // and value is "0=#hex" etc.
                    let parts = value.split(separator: "=", maxSplits: 1)
                    if parts.count == 2,
                       let idx = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                       idx >= 0, idx < 16 {
                        pal[idx] = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }

        return TerminalTheme(
            name: name,
            background: bg,
            foreground: fg,
            cursorColor: cursor,
            cursorText: cursorTxt,
            selectionBackground: selBg,
            selectionForeground: selFg,
            palette: pal
        )
    }

    /// Load a theme by name from the app bundle's Themes directory.
    static func load(name: String) -> TerminalTheme? {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Themes"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return parse(name: name, contents: contents)
    }

    /// List all available theme names from the bundle.
    static func availableThemes() -> [String] {
        guard let url = Bundle.main.url(forResource: "Themes", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return []
        }
        return files.sorted()
    }

    /// Build a Ghostty config string from this theme's colors.
    func toConfigString(backgroundOpacity: Double) -> String {
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
        lines.append("background-opacity = \(backgroundOpacity)")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Derive a UI Theme from this terminal theme's palette.
    func deriveUITheme() -> Theme {
        let bgColor = Color(hex: background)
        let fgColor = Color(hex: foreground)
        let pal15Color = Color(hex: palette[15])

        // Use brighter of foreground and palette[15] for text (HSB brightness)
        let textColor = Self.brighterColor(fgColor, pal15Color)

        // Accent: use cursor-color if it differs from foreground, else palette[4] (blue)
        let accentHex = (cursorColor.lowercased() != foreground.lowercased()) ? cursorColor : palette[4]

        return Theme(
            id: name,
            name: name,
            bg: bgColor,
            bg2: Self.adjustBrightness(bgColor, by: -0.08),
            border: Self.adjustBrightness(bgColor, by: 0.12),
            accent: Color(hex: accentHex),
            accent2: Color(hex: palette[6]),
            text: textColor,
            textMuted: textColor.opacity(0.6),
            textDim: textColor.opacity(0.4),
            danger: Color(hex: palette[1]),
            green: Color(hex: palette[2]),
            yellow: Color(hex: palette[3]),
            magenta: Color(hex: palette[5])
        )
    }

    // MARK: - Color Utilities

    private static func adjustBrightness(_ color: Color, by amount: Double) -> Color {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let newB = max(0, min(1, b + CGFloat(amount)))
        return Color(NSColor(hue: h, saturation: s, brightness: newB, alpha: a))
    }

    private static func brighterColor(_ a: Color, _ b: Color) -> Color {
        let nsA = NSColor(a).usingColorSpace(.sRGB) ?? NSColor(a)
        let nsB = NSColor(b).usingColorSpace(.sRGB) ?? NSColor(b)
        var bA: CGFloat = 0, bB: CGFloat = 0
        nsA.getHue(nil, saturation: nil, brightness: &bA, alpha: nil)
        nsB.getHue(nil, saturation: nil, brightness: &bB, alpha: nil)
        return bA >= bB ? a : b
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
git add Blink/Terminal/TerminalTheme.swift
git commit -m "feat: add TerminalTheme parser with UI color derivation"
```

---

## Chunk 2: ThemeManager & GhosttyApp Config Update

### Task 3: Overhaul ThemeManager

**Files:**
- Modify: `Blink/Theme/ThemeManager.swift`
- Modify: `Blink/Theme/Theme.swift`

- [ ] **Step 1: Update Theme.swift — remove hardcoded presets, keep struct**

Remove all 11 static theme presets and `allThemes`. Keep the `Theme` struct with its properties and a single default:

```swift
import SwiftUI

struct Theme {
    let id: String
    let name: String

    let bg: Color
    let bg2: Color
    let border: Color
    let accent: Color
    let accent2: Color
    let text: Color
    let textMuted: Color
    let textDim: Color
    let danger: Color
    let green: Color
    let yellow: Color
    let magenta: Color

    // Computed glow colors
    var accentGlow: Color { accent.opacity(0.2) }
    var accentGlowStrong: Color { accent.opacity(0.35) }
    var accent2Glow: Color { accent2.opacity(0.2) }
}
```

- [ ] **Step 2: Update ThemeManager.swift**

```swift
import SwiftUI

@Observable
final class ThemeManager {
    /// The currently active UI theme (derived from the terminal theme).
    var activeTheme: Theme

    /// The parsed terminal theme for the active selection.
    var activeTerminalTheme: TerminalTheme?

    /// All available theme names (filenames, not parsed).
    var availableThemes: [String] = []

    /// Cache of parsed themes (for color preview dots in picker).
    var parsedCache: [String: TerminalTheme] = [:]

    /// The 10 favorite theme names, pinned at top of the picker.
    static let favorites: [String] = [
        "Josean",
        "Dracula",
        "TokyoNight",
        "Catppuccin Mocha",
        "Gruvbox Dark",
        "Nord",
        "Atom One Dark",
        "Solarized Dark Patched",
        "Rose Pine",
        "Kanagawa Wave",
    ]

    init() {
        // Load theme names from bundle
        availableThemes = TerminalTheme.availableThemes()

        // Parse and apply default theme
        let defaultName = "Josean"
        if let theme = TerminalTheme.load(name: defaultName) {
            activeTerminalTheme = theme
            activeTheme = theme.deriveUITheme()
            parsedCache[defaultName] = theme
        } else {
            // Fallback: basic dark theme
            activeTheme = Theme(
                id: "fallback", name: "Fallback",
                bg: Color(hex: "#1a1b26"), bg2: Color(hex: "#16161e"),
                border: Color(hex: "#292e42"), accent: Color(hex: "#7aa2f7"),
                accent2: Color(hex: "#2ac3de"), text: Color(hex: "#c0caf5"),
                textMuted: Color(hex: "#c0caf5").opacity(0.6),
                textDim: Color(hex: "#c0caf5").opacity(0.4),
                danger: Color(hex: "#f7768e"), green: Color(hex: "#9ece6a"),
                yellow: Color(hex: "#e0af68"), magenta: Color(hex: "#bb9af7")
            )
        }
    }

    /// Switch to a theme by name. Parses the file and derives UI colors.
    func setTheme(name: String) {
        let theme: TerminalTheme
        if let cached = parsedCache[name] {
            theme = cached
        } else if let loaded = TerminalTheme.load(name: name) {
            parsedCache[name] = loaded
            theme = loaded
        } else {
            return
        }

        activeTerminalTheme = theme
        activeTheme = theme.deriveUITheme()
    }

    /// Get a parsed theme for preview (cached).
    func previewTheme(name: String) -> TerminalTheme? {
        if let cached = parsedCache[name] { return cached }
        if let loaded = TerminalTheme.load(name: name) {
            parsedCache[name] = loaded
            return loaded
        }
        return nil
    }
}

// SwiftUI Environment key for the active theme
private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: Theme = Theme(
        id: "default", name: "Default",
        bg: Color(hex: "#1a1b26"), bg2: Color(hex: "#16161e"),
        border: Color(hex: "#292e42"), accent: Color(hex: "#7aa2f7"),
        accent2: Color(hex: "#2ac3de"), text: Color(hex: "#c0caf5"),
        textMuted: Color(hex: "#c0caf5").opacity(0.6),
        textDim: Color(hex: "#c0caf5").opacity(0.4),
        danger: Color(hex: "#f7768e"), green: Color(hex: "#9ece6a"),
        yellow: Color(hex: "#e0af68"), magenta: Color(hex: "#bb9af7")
    )
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}
```

- [ ] **Step 3: Update AppStore.swift default theme**

Change the `theme` property default from `"ghostty"` to `"Josean"`:

In `AppStore.swift`, change:
```swift
var theme: String = "ghostty"
```
to:
```swift
var theme: String = "Josean"
```

- [ ] **Step 4: Verify build**

```bash
cd ~/Code/blink
xcodegen generate && xcodebuild -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add Blink/Theme/Theme.swift Blink/Theme/ThemeManager.swift Blink/Store/AppStore.swift
git commit -m "feat: overhaul ThemeManager to load from Ghostty theme files"
```

---

### Task 4: Add GhosttyApp.updateConfig()

**Files:**
- Modify: `Blink/Terminal/GhosttyApp.swift`

- [ ] **Step 1: Add updateConfig method**

Add this method to `GhosttyApp`:

```swift
    /// Hot-reload the terminal config with new theme colors and opacity.
    func updateConfig(terminalTheme: TerminalTheme, backgroundOpacity: Double) {
        guard let app else { return }

        let configString = terminalTheme.toConfigString(backgroundOpacity: backgroundOpacity)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-ghostty-\(UUID().uuidString)")
            .appendingPathExtension("conf")

        guard let _ = try? configString.write(to: tempURL, atomically: true, encoding: .utf8) else {
            print("[GhosttyApp] Failed to write temp config for update")
            return
        }

        guard let newCfg = ghostty_config_new() else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        ghostty_config_load_file(newCfg, tempURL.path)
        try? FileManager.default.removeItem(at: tempURL)
        ghostty_config_finalize(newCfg)

        ghostty_app_update_config(app, newCfg)

        // We own the config lifecycle — free old, keep new
        if let oldConfig = config {
            ghostty_config_free(oldConfig)
        }
        config = newCfg
    }
```

Also update the `init()` to use the Josean theme instead of hardcoded `background-opacity = 0.85`:

Replace the config string section in `init()` with:

```swift
        // Load the default theme for initial config
        let configString: String
        if let defaultTheme = TerminalTheme.load(name: "Josean") {
            configString = defaultTheme.toConfigString(backgroundOpacity: 0.85)
        } else {
            configString = "background-opacity = 0.85\n"
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
git add Blink/Terminal/GhosttyApp.swift
git commit -m "feat: add GhosttyApp.updateConfig() for hot-reloading theme and opacity"
```

---

## Chunk 3: Theme Picker & Settings Integration

### Task 5: Create ThemePicker modal

**Files:**
- Create: `Blink/Views/ThemePicker.swift`

- [ ] **Step 1: Write ThemePicker.swift**

```swift
import SwiftUI

struct ThemePicker: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    let ghosttyApp: GhosttyApp
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    private var filteredFavorites: [String] {
        let favs = ThemeManager.favorites.filter { themeManager.availableThemes.contains($0) }
        if searchText.isEmpty { return favs }
        return favs.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredAll: [String] {
        let nonFavs = themeManager.availableThemes.filter { !ThemeManager.favorites.contains($0) }
        if searchText.isEmpty { return nonFavs }
        return nonFavs.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var allItems: [String] {
        filteredFavorites + filteredAll
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Panel
            VStack(spacing: 0) {
                // Search input
                HStack(spacing: 8) {
                    Text(">")
                        .font(Fonts.primary(size: 14))
                        .foregroundStyle(theme.accent)
                    TextField("Search themes...", text: $searchText)
                        .font(Fonts.primary(size: 14))
                        .textFieldStyle(.plain)
                        .foregroundStyle(theme.text)
                        .focused($searchFocused)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Divider
                theme.border.frame(height: 1)

                // Scrollable list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if !filteredFavorites.isEmpty {
                                sectionHeader("FAVORITES")
                                ForEach(Array(filteredFavorites.enumerated()), id: \.element) { idx, name in
                                    themeRow(name: name, globalIndex: idx, proxy: proxy)
                                }
                            }

                            if !filteredAll.isEmpty {
                                sectionHeader("ALL")
                                ForEach(Array(filteredAll.enumerated()), id: \.element) { idx, name in
                                    let globalIdx = filteredFavorites.count + idx
                                    themeRow(name: name, globalIndex: globalIdx, proxy: proxy)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(width: 500, height: 450)
            .background(theme.bg)
            .overlay(
                Rectangle()
                    .stroke(theme.border, lineWidth: 1)
            )
            .onKeyPress(.upArrow) {
                selectedIndex = max(0, selectedIndex - 1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                selectedIndex = min(allItems.count - 1, selectedIndex + 1)
                return .handled
            }
            .onKeyPress(.return) {
                if selectedIndex < allItems.count {
                    applyTheme(allItems[selectedIndex])
                }
                return .handled
            }
            .onKeyPress(.escape) {
                onDismiss()
                return .handled
            }
        }
        .onAppear {
            searchFocused = true
            // Set initial selection to current theme
            if let idx = allItems.firstIndex(of: store.theme) {
                selectedIndex = idx
            }
        }
        .onChange(of: searchText) {
            selectedIndex = 0
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Fonts.primary(size: 11, weight: .medium))
            .foregroundStyle(theme.textDim)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func themeRow(name: String, globalIndex: Int, proxy: ScrollViewProxy) -> some View {
        let isSelected = globalIndex == selectedIndex
        let isCurrent = name == store.theme

        return Button {
            applyTheme(name)
        } label: {
            HStack {
                if isCurrent {
                    Text("✓")
                        .font(Fonts.primary(size: 12))
                        .foregroundStyle(theme.accent)
                        .frame(width: 16)
                } else {
                    Color.clear.frame(width: 16)
                }

                Text(name)
                    .font(Fonts.primary(size: 13))
                    .foregroundStyle(isSelected ? theme.text : theme.textMuted)
                    .lineLimit(1)

                Spacer()

                // Color preview dots
                if let parsed = themeManager.previewTheme(name: name) {
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: parsed.background)).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(theme.border, lineWidth: 0.5))
                        Circle().fill(Color(hex: parsed.foreground)).frame(width: 10, height: 10)
                        Circle().fill(Color(hex: parsed.palette[1])).frame(width: 10, height: 10)
                        Circle().fill(Color(hex: parsed.palette[2])).frame(width: 10, height: 10)
                        Circle().fill(Color(hex: parsed.palette[4])).frame(width: 10, height: 10)
                        Circle().fill(Color(hex: parsed.palette[5])).frame(width: 10, height: 10)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(isSelected ? theme.accent.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .id(name)
    }

    private func applyTheme(_ name: String) {
        store.theme = name
        themeManager.setTheme(name: name)
        if let termTheme = themeManager.activeTerminalTheme {
            ghosttyApp.updateConfig(terminalTheme: termTheme, backgroundOpacity: store.backgroundOpacity)
        }
        onDismiss()
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
git add Blink/Views/ThemePicker.swift
git commit -m "feat: add TUI-styled ThemePicker command palette modal"
```

---

### Task 6: Update AppearanceSettings & wire opacity

**Files:**
- Modify: `Blink/Views/Settings/AppearanceSettings.swift`
- Delete: `Blink/Views/Settings/ThemeCard.swift`

- [ ] **Step 1: Update AppearanceSettings.swift**

Replace the theme grid section with a "Change Theme" button and wire opacity to ghosttyApp:

```swift
import SwiftUI
import AppKit

struct AppearanceSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    let ghosttyApp: GhosttyApp

    @State private var showThemePicker = false

    private let wallpaperColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text("Appearance")
                        .font(Fonts.primary(size: 18, weight: .bold))
                        .foregroundStyle(theme.text)

                    // Theme section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Theme")
                            .font(Fonts.primary(size: 14, weight: .medium))
                            .foregroundStyle(theme.text)
                        Text("Color scheme for the app and terminal")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.textMuted)

                        Button {
                            showThemePicker = true
                        } label: {
                            HStack {
                                Text(store.theme)
                                    .font(Fonts.primary(size: 13))
                                    .foregroundStyle(theme.text)
                                Spacer()
                                Text("Change")
                                    .font(Fonts.primary(size: 12))
                                    .foregroundStyle(theme.accent)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(theme.bg2)
                            .overlay(
                                Rectangle()
                                    .stroke(theme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Background image section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Background image")
                            .font(Fonts.primary(size: 14, weight: .medium))
                            .foregroundStyle(theme.text)
                        Text("Show a wallpaper behind the content area")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.textMuted)

                        LazyVGrid(columns: wallpaperColumns, spacing: 12) {
                            WallpaperCard(
                                name: "None",
                                filename: nil,
                                isSelected: store.backgroundImage == nil,
                                onSelect: { store.setBackgroundImage(nil) }
                            )

                            ForEach(WallpaperPreset.all) { preset in
                                WallpaperCard(
                                    name: preset.name,
                                    filename: preset.filename,
                                    isSelected: store.backgroundImage == preset.id,
                                    onSelect: { store.setBackgroundImage(preset.id) }
                                )
                            }

                            WallpaperCard(
                                name: "Custom...",
                                filename: nil,
                                isSelected: store.backgroundImage != nil
                                    && !(store.backgroundImage!.hasPrefix("preset:")),
                                onSelect: { pickCustomWallpaper() }
                            )
                        }
                        .padding(.top, 4)
                    }

                    // Background opacity section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Background opacity")
                            .font(Fonts.primary(size: 14, weight: .medium))
                            .foregroundStyle(theme.text)
                        Text("How translucent the terminal overlay is (lower = more wallpaper visible)")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.textMuted)

                        HStack(spacing: 12) {
                            Slider(
                                value: Binding(
                                    get: { store.backgroundOpacity },
                                    set: { newValue in
                                        store.setBackgroundOpacity(newValue)
                                        // Hot-reload terminal opacity
                                        if let termTheme = themeManager.activeTerminalTheme {
                                            ghosttyApp.updateConfig(
                                                terminalTheme: termTheme,
                                                backgroundOpacity: newValue
                                            )
                                        }
                                    }
                                ),
                                in: 0.1...1.0,
                                step: 0.05
                            )
                            .disabled(!store.hasWallpaper)
                            .tint(theme.accent)

                            Text("\(Int(store.backgroundOpacity * 100))%")
                                .font(Fonts.primary(size: 12))
                                .foregroundStyle(theme.textMuted)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }

                    // Background blur section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Background blur")
                            .font(Fonts.primary(size: 14, weight: .medium))
                            .foregroundStyle(theme.text)
                        Text("Apply gaussian blur to the wallpaper image")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.textMuted)

                        HStack(spacing: 12) {
                            Slider(
                                value: Binding(
                                    get: { store.backgroundBlur },
                                    set: { store.setBackgroundBlur($0) }
                                ),
                                in: 0...32,
                                step: 1
                            )
                            .disabled(!store.hasWallpaper)
                            .tint(theme.accent)

                            Text("\(Int(store.backgroundBlur))px")
                                .font(Fonts.primary(size: 12))
                                .foregroundStyle(theme.textMuted)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showThemePicker {
                ThemePicker(
                    ghosttyApp: ghosttyApp,
                    onDismiss: { showThemePicker = false }
                )
            }
        }
    }

    private func pickCustomWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            store.setBackgroundImage(url.path)
        }
    }
}
```

- [ ] **Step 2: Delete ThemeCard.swift**

```bash
rm ~/Code/blink/Blink/Views/Settings/ThemeCard.swift
```

- [ ] **Step 3: Update SettingsPage.swift to pass ghosttyApp**

Check if SettingsPage wraps AppearanceSettings and pass ghosttyApp through.

- [ ] **Step 4: Update Shell.swift to pass ghosttyApp to SettingsPage**

The SettingsPage is rendered inside Shell.swift's content area. It needs access to ghosttyApp.

- [ ] **Step 5: Verify build**

```bash
cd ~/Code/blink
xcodegen generate && xcodebuild -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: theme picker + opacity wiring + remove old theme grid"
```

---

## Chunk 4: Final Integration & Testing

### Task 7: Run and verify

- [ ] **Step 1: Build and launch**

```bash
cd ~/Code/blink
xcodebuild -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -3
open ~/Library/Developer/Xcode/DerivedData/Blink-*/Build/Products/Debug/Blink.app
```

- [ ] **Step 2: Verify success criteria**

1. Open Settings → click "Change Theme"
2. Theme picker appears as a centered modal with TUI styling
3. Search filters themes in real time
4. Favorites appear at the top
5. Selecting a theme updates both UI chrome and terminal colors
6. Escape closes the picker
7. Opacity slider updates terminal transparency in real time

- [ ] **Step 3: Final commit if any fixes needed**
