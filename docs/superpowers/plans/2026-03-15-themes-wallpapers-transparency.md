# Themes, Wallpapers & Transparency — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add all 11 theme presets with a settings UI, wallpaper backgrounds with opacity/blur controls, and transparent UI layers over wallpapers.

**Architecture:** Extend the existing Theme struct with 10 new presets. Add a full-screen settings overlay with an Appearance tab containing theme cards, wallpaper thumbnails, and sliders. Wrap Shell's existing layout in a ZStack to layer wallpaper images behind semi-transparent views.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 14+, XcodeGen

**Spec:** `docs/superpowers/specs/2026-03-15-themes-wallpapers-transparency-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Blink/Theme/Theme.swift` | Modify | Add 10 remaining theme presets + `allThemes` array |
| `Blink/Theme/ThemeManager.swift` | Modify | Add `setTheme(id:)` method |
| `Blink/Store/AppStore.swift` | Modify | Add `ActiveView` enum, background properties |
| `Blink/Models/WallpaperPreset.swift` | Create | Wallpaper preset data model + registry |
| `Blink/Views/SettingsPage.swift` | Create | Full-screen settings overlay with tab nav |
| `Blink/Views/Settings/AppearanceSettings.swift` | Create | Theme grid, wallpaper grid, sliders |
| `Blink/Views/Settings/ThemeCard.swift` | Create | Individual theme picker card |
| `Blink/Views/Settings/WallpaperCard.swift` | Create | Wallpaper thumbnail card |
| `Blink/BApp.swift` | Modify | Inject ThemeManager into environment |
| `Blink/Views/Shell.swift` | Modify | ZStack wallpaper layer, settings overlay, transparency |
| `Blink/Views/Sidebar.swift` | Modify | Conditional transparent background |
| `Blink/Views/TabBar.swift` | Modify | Conditional transparent background |
| `Blink/Views/StatusLine.swift` | Modify | Conditional transparent background |
| `Blink/Resources/Wallpapers/` | Add | 8 wallpaper image files |

---

## Chunk 1: Theme Presets + State

### Task 1: Add all theme presets to Theme.swift

**Files:**
- Modify: `Blink/Theme/Theme.swift`

- [ ] **Step 1: Add 10 remaining theme presets and `allThemes` array**

Add these static presets to `extension Theme` (after the existing `.cyberpunk`). All hex values from Krux's `themes.ts`:

```swift
extension Theme {
    // ... existing .cyberpunk ...

    static let josean = Theme(
        id: "josean", name: "Josean",
        bg: Color(hex: "#011423"), bg2: Color(hex: "#01101c"),
        border: Color(hex: "#033259"), accent: Color(hex: "#47ff9c"),
        accent2: Color(hex: "#0fc5ed"), text: Color(hex: "#cbe0f0"),
        textMuted: Color(hex: "#7a9ab8"), textDim: Color(hex: "#4a6580"),
        danger: Color(hex: "#e52e2e"), green: Color(hex: "#44ffb1"),
        yellow: Color(hex: "#ffe073"), magenta: Color(hex: "#a277ff")
    )

    static let dracula = Theme(
        id: "dracula", name: "Dracula",
        bg: Color(hex: "#282a36"), bg2: Color(hex: "#21222c"),
        border: Color(hex: "#44475a"), accent: Color(hex: "#bd93f9"),
        accent2: Color(hex: "#8be9fd"), text: Color(hex: "#f8f8f2"),
        textMuted: Color(hex: "#8893b8"), textDim: Color(hex: "#626580"),
        danger: Color(hex: "#ff5555"), green: Color(hex: "#50fa7b"),
        yellow: Color(hex: "#f1fa8c"), magenta: Color(hex: "#ff79c6")
    )

    static let tokyoNight = Theme(
        id: "tokyo-night", name: "Tokyo Night",
        bg: Color(hex: "#1a1b26"), bg2: Color(hex: "#16161e"),
        border: Color(hex: "#292e42"), accent: Color(hex: "#7aa2f7"),
        accent2: Color(hex: "#2ac3de"), text: Color(hex: "#c0caf5"),
        textMuted: Color(hex: "#7982a8"), textDim: Color(hex: "#565d80"),
        danger: Color(hex: "#f7768e"), green: Color(hex: "#9ece6a"),
        yellow: Color(hex: "#e0af68"), magenta: Color(hex: "#bb9af7")
    )

    static let catppuccinMocha = Theme(
        id: "catppuccin-mocha", name: "Catppuccin Mocha",
        bg: Color(hex: "#1e1e2e"), bg2: Color(hex: "#181825"),
        border: Color(hex: "#313244"), accent: Color(hex: "#cba6f7"),
        accent2: Color(hex: "#89dceb"), text: Color(hex: "#cdd6f4"),
        textMuted: Color(hex: "#8f93a8"), textDim: Color(hex: "#626478"),
        danger: Color(hex: "#f38ba8"), green: Color(hex: "#a6e3a1"),
        yellow: Color(hex: "#f9e2af"), magenta: Color(hex: "#f5c2e7")
    )

    static let gruvboxDark = Theme(
        id: "gruvbox-dark", name: "Gruvbox Dark",
        bg: Color(hex: "#282828"), bg2: Color(hex: "#1d2021"),
        border: Color(hex: "#3c3836"), accent: Color(hex: "#fabd2f"),
        accent2: Color(hex: "#83a598"), text: Color(hex: "#ebdbb2"),
        textMuted: Color(hex: "#a89984"), textDim: Color(hex: "#665c54"),
        danger: Color(hex: "#fb4934"), green: Color(hex: "#b8bb26"),
        yellow: Color(hex: "#fabd2f"), magenta: Color(hex: "#d3869b")
    )

    static let nord = Theme(
        id: "nord", name: "Nord",
        bg: Color(hex: "#2e3440"), bg2: Color(hex: "#272c36"),
        border: Color(hex: "#3b4252"), accent: Color(hex: "#88c0d0"),
        accent2: Color(hex: "#81a1c1"), text: Color(hex: "#eceff4"),
        textMuted: Color(hex: "#9aa5b4"), textDim: Color(hex: "#616e7c"),
        danger: Color(hex: "#bf616a"), green: Color(hex: "#a3be8c"),
        yellow: Color(hex: "#ebcb8b"), magenta: Color(hex: "#b48ead")
    )

    static let oneDark = Theme(
        id: "one-dark", name: "One Dark",
        bg: Color(hex: "#282c34"), bg2: Color(hex: "#21252b"),
        border: Color(hex: "#3e4452"), accent: Color(hex: "#61afef"),
        accent2: Color(hex: "#56b6c2"), text: Color(hex: "#abb2bf"),
        textMuted: Color(hex: "#7f848e"), textDim: Color(hex: "#5c6370"),
        danger: Color(hex: "#e06c75"), green: Color(hex: "#98c379"),
        yellow: Color(hex: "#e5c07b"), magenta: Color(hex: "#c678dd")
    )

    static let solarizedDark = Theme(
        id: "solarized-dark", name: "Solarized Dark",
        bg: Color(hex: "#002b36"), bg2: Color(hex: "#00252f"),
        border: Color(hex: "#073642"), accent: Color(hex: "#b58900"),
        accent2: Color(hex: "#268bd2"), text: Color(hex: "#839496"),
        textMuted: Color(hex: "#657b83"), textDim: Color(hex: "#586e75"),
        danger: Color(hex: "#dc322f"), green: Color(hex: "#859900"),
        yellow: Color(hex: "#b58900"), magenta: Color(hex: "#d33682")
    )

    static let rosePine = Theme(
        id: "rose-pine", name: "Rosé Pine",
        bg: Color(hex: "#191724"), bg2: Color(hex: "#1f1d2e"),
        border: Color(hex: "#26233a"), accent: Color(hex: "#ebbcba"),
        accent2: Color(hex: "#31748f"), text: Color(hex: "#e0def4"),
        textMuted: Color(hex: "#908caa"), textDim: Color(hex: "#6e6a86"),
        danger: Color(hex: "#eb6f92"), green: Color(hex: "#9ccfd8"),
        yellow: Color(hex: "#f6c177"), magenta: Color(hex: "#c4a7e7")
    )

    static let kanagawa = Theme(
        id: "kanagawa", name: "Kanagawa",
        bg: Color(hex: "#1f1f28"), bg2: Color(hex: "#16161d"),
        border: Color(hex: "#2a2a37"), accent: Color(hex: "#dca561"),
        accent2: Color(hex: "#7e9cd8"), text: Color(hex: "#dcd7ba"),
        textMuted: Color(hex: "#9a9a8e"), textDim: Color(hex: "#727169"),
        danger: Color(hex: "#e82424"), green: Color(hex: "#98bb6c"),
        yellow: Color(hex: "#e6c384"), magenta: Color(hex: "#957fb8")
    )

    /// All available themes in display order.
    static let allThemes: [Theme] = [
        .cyberpunk, .josean, .dracula, .tokyoNight, .catppuccinMocha,
        .gruvboxDark, .nord, .oneDark, .solarizedDark, .rosePine, .kanagawa
    ]
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Blink/Theme/Theme.swift
git commit -m "feat: add all 11 theme presets"
```

---

### Task 2: ThemeManager switching + environment injection

**Files:**
- Modify: `Blink/Theme/ThemeManager.swift`
- Modify: `Blink/BApp.swift`

- [ ] **Step 1: Add setTheme method to ThemeManager**

```swift
import SwiftUI

@Observable
final class ThemeManager {
    var activeTheme: Theme = .cyberpunk

    func setTheme(id: String) {
        if let theme = Theme.allThemes.first(where: { $0.id == id }) {
            activeTheme = theme
        }
    }
}

// ... existing EnvironmentKey code unchanged ...
```

- [ ] **Step 2: Inject ThemeManager into environment in BApp.swift**

Add `.environment(themeManager)` so settings views can access it:

```swift
@main
struct BApp: App {
    @State private var themeManager = ThemeManager()
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            Shell()
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

- [ ] **Step 3: Build, commit**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
git add Blink/Theme/ThemeManager.swift Blink/BApp.swift
git commit -m "feat: add theme switching and ThemeManager environment injection"
```

---

### Task 3: AppStore additions (activeView, background properties)

**Files:**
- Modify: `Blink/Store/AppStore.swift`

- [ ] **Step 1: Add ActiveView enum and background properties**

Add at the top of the file before the class:

```swift
enum ActiveView {
    case projects
    case settings
}
```

Add to the AppStore class:

```swift
    // View
    var activeView: ActiveView = .projects

    // Background
    var backgroundImage: String? = nil
    var backgroundOpacity: Double = 0.75
    var backgroundBlur: Double = 0

    // MARK: - View Actions

    func setActiveView(_ view: ActiveView) {
        activeView = view
    }

    // MARK: - Background Actions

    func setBackgroundImage(_ image: String?) {
        backgroundImage = image
    }

    func setBackgroundOpacity(_ opacity: Double) {
        backgroundOpacity = max(0.1, min(1.0, opacity))
    }

    func setBackgroundBlur(_ blur: Double) {
        backgroundBlur = max(0, min(32, blur))
    }

    /// Whether a wallpaper is currently active.
    var hasWallpaper: Bool {
        backgroundImage != nil
    }
```

- [ ] **Step 2: Build, run tests, commit**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
xcodebuild test -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' 2>&1 | tail -10
git add Blink/Store/AppStore.swift
git commit -m "feat: add ActiveView enum and background properties to AppStore"
```

---

### Task 4: WallpaperPreset model

**Files:**
- Create: `Blink/Models/WallpaperPreset.swift`

- [ ] **Step 1: Create WallpaperPreset model**

```swift
import Foundation

struct WallpaperPreset: Identifiable, Equatable {
    let id: String       // e.g. "preset:ship-at-sea"
    let name: String     // e.g. "Ship at Sea"
    let filename: String // e.g. "ship-at-sea.jpg"
}

extension WallpaperPreset {
    static let all: [WallpaperPreset] = [
        WallpaperPreset(id: "preset:ship-at-sea", name: "Ship at Sea", filename: "ship-at-sea.jpg"),
        WallpaperPreset(id: "preset:akane-pagoda", name: "Akane Pagoda", filename: "akane-pagoda.jpg"),
        WallpaperPreset(id: "preset:everforest", name: "Everforest", filename: "everforest.jpg"),
        WallpaperPreset(id: "preset:gruvbox-ferns", name: "Gruvbox Ferns", filename: "gruvbox-ferns.jpg"),
        WallpaperPreset(id: "preset:akane-cliff", name: "Akane Cliff", filename: "akane-cliff.jpg"),
        WallpaperPreset(id: "preset:akane-bridge", name: "Akane Bridge", filename: "akane-bridge.jpg"),
        WallpaperPreset(id: "preset:akane-mist", name: "Akane Mist", filename: "akane-mist.jpg"),
        WallpaperPreset(id: "preset:pink-lakeside", name: "Pink Lakeside", filename: "pink-lakeside.png"),
    ]

    /// Look up a preset by its ID. Returns nil for custom wallpapers.
    static func find(_ id: String) -> WallpaperPreset? {
        all.first { $0.id == id }
    }
}
```

- [ ] **Step 2: Regenerate project, build, commit**

```bash
xcodegen generate
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
git add Blink/Models/WallpaperPreset.swift Blink.xcodeproj
git commit -m "feat: add WallpaperPreset model with 8 presets"
```

---

### Task 5: Bundle wallpaper images

**Files:**
- Add: `Blink/Resources/Wallpapers/*.jpg` and `*.png`
- Modify: `project.yml` (add resources)

- [ ] **Step 1: Copy wallpaper images from Krux**

```bash
mkdir -p Blink/Resources/Wallpapers
cp /Users/bradley/Code/krux/src/renderer/public/wallpapers/*.jpg Blink/Resources/Wallpapers/
cp /Users/bradley/Code/krux/src/renderer/public/wallpapers/*.png Blink/Resources/Wallpapers/
```

- [ ] **Step 2: Update project.yml to include resources**

Add a resources section to the Blink target:

```yaml
targets:
  Blink:
    type: application
    platform: macOS
    sources:
      - Blink
    resources:
      - path: Blink/Resources
        buildPhase: resources
    settings:
      # ... existing settings ...
```

- [ ] **Step 3: Regenerate project, build, commit**

```bash
xcodegen generate
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
git add Blink/Resources/ project.yml Blink.xcodeproj
git commit -m "feat: bundle 8 wallpaper images from Krux"
```

---

## Chunk 2: Settings Page UI

### Task 6: SettingsPage overlay

**Files:**
- Create: `Blink/Views/SettingsPage.swift`

- [ ] **Step 1: Create SettingsPage.swift**

```swift
import SwiftUI

struct SettingsPage: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    enum SettingsTab: String, CaseIterable {
        case appearance = "Appearance"
        case terminal = "Terminal"
        case keyboardShortcuts = "Keyboard Shortcuts"
    }

    @State private var selectedTab: SettingsTab = .appearance
    @State private var isBackHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: back button
            Button(action: { store.setActiveView(.projects) }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                    Text("Settings")
                        .font(Fonts.primary(size: 16, weight: .bold))
                }
                .foregroundStyle(isBackHovered ? theme.text : theme.textMuted)
            }
            .buttonStyle(.plain)
            .onHover { isBackHovered = $0 }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Body: nav sidebar + content
            HStack(alignment: .top, spacing: 0) {
                // Nav sidebar
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        let isActive = selectedTab == tab
                        let isDisabled = tab != .appearance

                        Button(action: { if !isDisabled { selectedTab = tab } }) {
                            Text(tab.rawValue)
                                .font(Fonts.primary(size: 14))
                                .foregroundStyle(
                                    isDisabled ? theme.textDim :
                                    isActive ? theme.text : theme.textMuted
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    isActive ? Color.white.opacity(0.06) :
                                    Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(isDisabled)
                    }
                }
                .frame(width: 180)
                .padding(.trailing, 16)

                // Content divider
                theme.border.frame(width: 1)

                // Content area
                ScrollView(.vertical, showsIndicators: true) {
                    switch selectedTab {
                    case .appearance:
                        AppearanceSettings()
                    case .terminal:
                        Text("Terminal settings coming soon")
                            .font(Fonts.primary(size: 14))
                            .foregroundStyle(theme.textDim)
                            .padding(32)
                    case .keyboardShortcuts:
                        Text("Keyboard shortcuts coming soon")
                            .font(Fonts.primary(size: 14))
                            .foregroundStyle(theme.textDim)
                            .padding(32)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: 1024)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bg)
    }
}
```

- [ ] **Step 2: Create placeholder AppearanceSettings.swift**

Create `Blink/Views/Settings/AppearanceSettings.swift`:

```swift
import SwiftUI

struct AppearanceSettings: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("Appearance")
                .font(Fonts.primary(size: 18, weight: .bold))
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 3: Wire SettingsPage into Shell.swift**

Modify Shell.swift to show the settings overlay when `activeView == .settings`:

```swift
    var body: some View {
        ZStack {
            // Main layout
            VStack(spacing: 0) {
                // ... existing tab bar + HStack layout ...
            }
            .background(theme.bg)
            .font(Fonts.primary(size: 13))

            // Settings overlay
            if store.activeView == .settings {
                SettingsPage()
            }
        }
    }
```

- [ ] **Step 4: Wire sidebar Settings button**

In `Blink/Views/Sidebar.swift`, replace the settings button no-op:

```swift
Button(action: { store.setActiveView(.settings) }) {
```

This requires adding `@Environment(AppStore.self) private var store` to SidebarView if not already there (it is already there).

- [ ] **Step 5: Regenerate, build, test visually**

```bash
mkdir -p Blink/Views/Settings
xcodegen generate
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Launch app, click Settings button — should see the settings overlay with "Appearance" text.

- [ ] **Step 6: Commit**

```bash
git add Blink/Views/SettingsPage.swift Blink/Views/Settings/ Blink/Views/Shell.swift Blink/Views/Sidebar.swift Blink.xcodeproj
git commit -m "feat: add SettingsPage overlay with tab navigation"
```

---

### Task 7: ThemeCard component

**Files:**
- Create: `Blink/Views/Settings/ThemeCard.swift`

- [ ] **Step 1: Create ThemeCard.swift**

```swift
import SwiftUI

struct ThemeCard: View {
    let theme: Theme
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Three color preview dots
                HStack(spacing: 4) {
                    Circle().fill(theme.accent).frame(width: 12, height: 12)
                    Circle().fill(theme.accent2).frame(width: 12, height: 12)
                    Circle().fill(theme.bg).frame(width: 12, height: 12)
                        .overlay(
                            Circle().stroke(theme.border, lineWidth: 1)
                        )
                }

                Text(theme.name)
                    .font(Fonts.primary(size: 13))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? theme.accent : theme.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Regenerate, build, commit**

```bash
xcodegen generate
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
git add Blink/Views/Settings/ThemeCard.swift Blink.xcodeproj
git commit -m "feat: add ThemeCard component with color dots preview"
```

---

### Task 8: WallpaperCard component

**Files:**
- Create: `Blink/Views/Settings/WallpaperCard.swift`

- [ ] **Step 1: Create WallpaperCard.swift**

```swift
import SwiftUI

struct WallpaperCard: View {
    @Environment(\.theme) private var theme

    let name: String
    let imageName: String?  // nil for "None" and "Custom..." cards
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottom) {
                if let imageName {
                    // Preset wallpaper thumbnail
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 100)
                        .clipped()
                } else {
                    // Plain card for "None" / "Custom..."
                    theme.bg2
                        .frame(height: 100)
                }

                // Name label at bottom
                Text(name)
                    .font(Fonts.primary(size: 11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.5))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? theme.accent : theme.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Regenerate, build, commit**

```bash
xcodegen generate
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
git add Blink/Views/Settings/WallpaperCard.swift Blink.xcodeproj
git commit -m "feat: add WallpaperCard component with thumbnail preview"
```

---

### Task 9: AppearanceSettings (full implementation)

**Files:**
- Modify: `Blink/Views/Settings/AppearanceSettings.swift`

- [ ] **Step 1: Replace AppearanceSettings with full implementation**

```swift
import SwiftUI
import AppKit

struct AppearanceSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    private let themeColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private let wallpaperColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Section: Appearance header
            Text("Appearance")
                .font(Fonts.primary(size: 18, weight: .bold))
                .foregroundStyle(theme.text)

            // Section: Theme
            VStack(alignment: .leading, spacing: 8) {
                Text("Theme")
                    .font(Fonts.primary(size: 14, weight: .medium))
                    .foregroundStyle(theme.text)
                Text("Choose a color scheme for the app")
                    .font(Fonts.primary(size: 12))
                    .foregroundStyle(theme.textMuted)

                LazyVGrid(columns: themeColumns, spacing: 12) {
                    ForEach(Theme.allThemes, id: \.id) { preset in
                        ThemeCard(
                            theme: preset,
                            isSelected: store.theme == preset.id,
                            onSelect: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    store.theme = preset.id
                                    themeManager.setTheme(id: preset.id)
                                }
                            }
                        )
                    }
                }
                .padding(.top, 4)
            }

            // Section: Background image
            VStack(alignment: .leading, spacing: 8) {
                Text("Background image")
                    .font(Fonts.primary(size: 14, weight: .medium))
                    .foregroundStyle(theme.text)
                Text("Show a wallpaper behind the content area")
                    .font(Fonts.primary(size: 12))
                    .foregroundStyle(theme.textMuted)

                LazyVGrid(columns: wallpaperColumns, spacing: 12) {
                    // "None" card
                    WallpaperCard(
                        name: "None",
                        imageName: nil,
                        isSelected: store.backgroundImage == nil,
                        onSelect: { store.setBackgroundImage(nil) }
                    )

                    // Preset wallpapers
                    ForEach(WallpaperPreset.all) { preset in
                        WallpaperCard(
                            name: preset.name,
                            imageName: preset.filename.replacingOccurrences(of: ".jpg", with: "")
                                .replacingOccurrences(of: ".png", with: ""),
                            isSelected: store.backgroundImage == preset.id,
                            onSelect: { store.setBackgroundImage(preset.id) }
                        )
                    }

                    // "Custom..." card
                    WallpaperCard(
                        name: "Custom...",
                        imageName: nil,
                        isSelected: store.backgroundImage != nil
                            && !store.backgroundImage!.hasPrefix("preset:"),
                        onSelect: { pickCustomWallpaper() }
                    )
                }
                .padding(.top, 4)
            }

            // Section: Hide titlebar
            VStack(alignment: .leading, spacing: 8) {
                Text("Hide titlebar")
                    .font(Fonts.primary(size: 14, weight: .medium))
                    .foregroundStyle(theme.text)
                Text("Remove the native window titlebar for a cleaner look")
                    .font(Fonts.primary(size: 12))
                    .foregroundStyle(theme.textMuted)

                Toggle("", isOn: .constant(false))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(true)
                    .opacity(0.5)
            }

            // Section: Background opacity
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
                            set: { store.setBackgroundOpacity($0) }
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

            // Section: Background blur
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

Note: The `Image(imageName)` in WallpaperCard loads from the app bundle by name (without extension). This requires the wallpaper files to be in the bundle's resources. XcodeGen's resource configuration from Task 5 handles this.

- [ ] **Step 2: Regenerate, build, verify**

```bash
xcodegen generate
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Launch app, click Settings → Appearance. Should see theme grid, wallpaper grid, sliders.

- [ ] **Step 3: Commit**

```bash
git add Blink/Views/Settings/AppearanceSettings.swift Blink.xcodeproj
git commit -m "feat: implement AppearanceSettings with theme/wallpaper/slider controls"
```

---

## Chunk 3: Wallpaper Rendering + Transparency

### Task 10: Shell wallpaper layer + transparency

**Files:**
- Modify: `Blink/Views/Shell.swift`

- [ ] **Step 1: Add wallpaper ZStack and transparency to Shell**

Replace Shell.swift body with:

```swift
    var body: some View {
        ZStack {
            // Wallpaper layer (behind everything)
            if let wallpaperId = store.backgroundImage {
                wallpaperImage(for: wallpaperId)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(1.1) // Prevent visible edges when blurred
                    .blur(radius: store.backgroundBlur)
                    .clipped()
                    .ignoresSafeArea()
            }

            // Main layout
            VStack(spacing: 0) {
                TabBarView()
                    .frame(height: Layout.tabBarHeight)

                HStack(spacing: 0) {
                    SidebarView()
                        .frame(width: Layout.sidebarWidth)

                    theme.border.frame(width: 1)

                    VStack(spacing: 0) {
                        ZStack {
                            if store.hasWallpaper {
                                theme.bg.opacity(store.backgroundOpacity)
                            } else {
                                theme.bg
                            }
                            if store.activeProjectId == nil {
                                StartScreen()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        theme.border.frame(height: 1)

                        StatusLine()
                            .frame(height: Layout.statusLineHeight)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .font(Fonts.primary(size: 13))

            // Settings overlay
            if store.activeView == .settings {
                SettingsPage()
            }
        }
        .background(theme.bg)
    }

    /// Load wallpaper image from preset or custom file path.
    private func wallpaperImage(for id: String) -> Image {
        if let preset = WallpaperPreset.find(id) {
            let name = preset.filename
                .replacingOccurrences(of: ".jpg", with: "")
                .replacingOccurrences(of: ".png", with: "")
            return Image(name)
        } else {
            // Custom file path
            if let nsImage = NSImage(contentsOfFile: id) {
                return Image(nsImage: nsImage)
            }
            return Image(systemName: "photo")
        }
    }
```

- [ ] **Step 2: Build, commit**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
git add Blink/Views/Shell.swift
git commit -m "feat: add wallpaper ZStack layer and settings overlay to Shell"
```

---

### Task 11: Transparent backgrounds for Sidebar, TabBar, StatusLine

**Files:**
- Modify: `Blink/Views/Sidebar.swift`
- Modify: `Blink/Views/TabBar.swift`
- Modify: `Blink/Views/StatusLine.swift`

- [ ] **Step 1: Update Sidebar background**

In `Blink/Views/Sidebar.swift`, change the `.background(theme.bg2)` line to:

```swift
        .background(
            store.hasWallpaper
                ? AnyShapeStyle(theme.bg2.opacity(store.backgroundOpacity))
                : AnyShapeStyle(theme.bg2)
        )
```

Note: SidebarView already has `@Environment(AppStore.self) private var store`.

- [ ] **Step 2: Update TabBar background**

In `Blink/Views/TabBar.swift`, change the `.background(theme.bg2)` line to:

```swift
        .background(
            store.hasWallpaper
                ? AnyShapeStyle(theme.bg2.opacity(store.backgroundOpacity))
                : AnyShapeStyle(theme.bg2)
        )
```

TabBarView already has `@Environment(AppStore.self) private var store`.

- [ ] **Step 3: Update StatusLine background**

In `Blink/Views/StatusLine.swift`, change the `.background(theme.bg)` line to:

```swift
        .background(
            store.hasWallpaper
                ? AnyShapeStyle(theme.bg.opacity(store.backgroundOpacity))
                : AnyShapeStyle(theme.bg)
        )
```

StatusLine already has `@Environment(AppStore.self) private var store`.

- [ ] **Step 4: Build, commit**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
git add Blink/Views/Sidebar.swift Blink/Views/TabBar.swift Blink/Views/StatusLine.swift
git commit -m "feat: add conditional transparent backgrounds for wallpaper mode"
```

---

### Task 12: Visual verification

- [ ] **Step 1: Clean build and launch**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' clean build 2>&1 | tail -5
```

Launch the app.

- [ ] **Step 2: Verify theme switching**

- Open Settings → Appearance
- Click through all 11 theme cards
- Verify each theme recolors the entire app (sidebar, tab bar, status line, settings page itself)
- Verify the color dots on each card show that theme's accent, accent2, and bg colors

- [ ] **Step 3: Verify wallpaper**

- Select "Ship at Sea" wallpaper
- Verify the image appears behind the sidebar, tab bar, and content area
- Verify sidebar, tab bar, and status line become semi-transparent
- Adjust opacity slider — verify transparency changes in real-time
- Adjust blur slider — verify blur effect changes
- Select "None" — verify wallpaper disappears and backgrounds return to opaque
- Try "Custom..." — verify file picker opens and custom image loads

- [ ] **Step 4: Verify theme + wallpaper combination**

- Set a wallpaper, then switch themes
- Verify the transparent overlays change color with the theme

- [ ] **Step 5: Run all tests**

```bash
xcodebuild test -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' 2>&1 | tail -10
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: complete Milestone 2 — themes, wallpapers, transparency"
```
