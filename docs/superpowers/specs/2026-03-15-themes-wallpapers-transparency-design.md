# Blink — Milestone 2: Themes, Wallpapers & Transparency

## Overview

Add the full theme system (11 presets), wallpaper backgrounds with blur/opacity controls, and transparent UI layers. Includes a settings page with an Appearance tab to control all of these. Terminal and Keyboard Shortcuts tabs are visible but non-functional.

**Success criteria:** Change themes and see the entire app recolor instantly. Set a wallpaper and see it behind semi-transparent sidebar/tab bar/status line. Adjust opacity and blur sliders and see the effect in real-time.

## Settings Page

### Layout

Full-screen overlay rendered on top of the Shell at highest z-index. Dismisses via back button.

```
┌──────────────────────────────────────────────────────────┐
│  < Settings                                              │
├─────────────────┬────────────────────────────────────────┤
│  Appearance ◄── │  Appearance                            │
│  Terminal       │                                        │
│  Keyboard       │  [Theme section]                       │
│  Shortcuts      │  [Background image section]            │
│                 │  [Hide titlebar toggle]                │
│                 │  [Background opacity slider]           │
│                 │  [Background blur slider]              │
│                 │                                        │
└─────────────────┴────────────────────────────────────────┘
```

**Back button:** "< Settings" text button, top-left, 16pt font, textMuted, hover → text. Dismisses the settings overlay.

**Tab sidebar:**
- Width: ~200pt
- Items: "Appearance" (active), "Terminal" (disabled, textDim), "Keyboard Shortcuts" (disabled, textDim)
- Active item: subtle bg highlight (white/6%), accent-colored text or text color
- Font: 14pt, Fonts.primary

**Content area:**
- Scrollable vertically
- Padding: 32pt horizontal, 24pt top
- Background: theme.bg

### Triggering

Add `activeView: ActiveView` enum (`.projects`, `.settings`) to AppStore. The Settings button in the sidebar footer sets `activeView = .settings`. When `activeView == .settings`, Shell renders the SettingsPage as a full-screen overlay that covers the entire Shell including the sidebar. The back button dismisses by setting `activeView = .projects`.

The settings page is a centered, max-width container (~1024pt) with a nav column (auto-width) and a content pane separated by a left border. The nav sidebar remains fixed/sticky while the content area scrolls. Disabled tabs (Terminal, Keyboard Shortcuts) show placeholder text when clicked.

## Theme System

### All 11 Theme Presets

Port all themes from Krux's `themes.ts`. The `Theme` struct and `Color(hex:)` are already built. Add 10 new static presets:

| Key | Display Name | Accent | Accent2 |
|-----|-------------|--------|---------|
| `ghostty` | Cyberpunk | `#c8ff00` | `#0fc5ed` |
| `josean` | Josean | `#47ff9c` | `#0fc5ed` |
| `dracula` | Dracula | `#bd93f9` | `#8be9fd` |
| `tokyo-night` | Tokyo Night | `#7aa2f7` | `#2ac3de` |
| `catppuccin-mocha` | Catppuccin Mocha | `#cba6f7` | `#89dceb` |
| `gruvbox-dark` | Gruvbox Dark | `#fabd2f` | `#83a598` |
| `nord` | Nord | `#88c0d0` | `#81a1c1` |
| `one-dark` | One Dark | `#61afef` | `#56b6c2` |
| `solarized-dark` | Solarized Dark | `#b58900` | `#268bd2` |
| `rose-pine` | Rosé Pine | `#ebbcba` | `#31748f` |
| `kanagawa` | Kanagawa | `#dca561` | `#7e9cd8` |

All hex values from the existing `themes.ts` in Krux (already verified in M1).

### Theme Card UI

Each theme is a rounded rectangle card showing:
- 3 color dots: showing representative colors from the theme (accent, accent2, and a third color like green or magenta)
- Theme display name
- Border: `border` color normally, `accent` color when selected
- Background: `bg2` color of that theme (so each card previews its own colors)
- Grid: 3 columns, responsive

### Theme Switching

- `ThemeManager.setTheme(id:)` looks up the theme by key and sets `activeTheme`
- All views react via `@Environment(\.theme)`. Use `withAnimation(.easeInOut(duration: 0.15))` around theme changes for smooth transitions.
- `AppStore.theme` stores the active theme ID string
- `ThemeManager` must be injected into the environment via `.environment(themeManager)` in BApp.swift so settings views can call `setTheme(id:)` using `@Environment(ThemeManager.self)`

### Theme Card Color Dots

Each theme card shows 3 small colored circles representing that theme's palette. The dots use colors from the theme being previewed (not the active theme):
- Dot 1: theme's `accent` color
- Dot 2: theme's `accent2` color
- Dot 3: theme's `bg` color

## Wallpaper System

### Preset Wallpapers

8 bundled wallpaper images matching Krux:

| ID | Name | Filename |
|----|------|----------|
| `preset:ship-at-sea` | Ship at Sea | `ship-at-sea.jpg` |
| `preset:akane-pagoda` | Akane Pagoda | `akane-pagoda.jpg` |
| `preset:everforest` | Everforest | `everforest.jpg` |
| `preset:gruvbox-ferns` | Gruvbox Ferns | `gruvbox-ferns.jpg` |
| `preset:akane-cliff` | Akane Cliff | `akane-cliff.jpg` |
| `preset:akane-bridge` | Akane Bridge | `akane-bridge.jpg` |
| `preset:akane-mist` | Akane Mist | `akane-mist.jpg` |
| `preset:pink-lakeside` | Pink Lakeside | `pink-lakeside.png` |

Images are bundled in the app's Resources folder. Source images copied from Krux's `public/wallpapers/` directory.

### Wallpaper Card UI

- Grid: 4 columns
- Each card: thumbnail image with rounded corners, name label overlaid at bottom
- "None" card: plain bg2 background, "None" text centered
- "Custom..." card: plain bg2 background, "Custom..." text, opens `NSOpenPanel` for image file selection
- Selected card: accent border highlight
- Thumbnail size: ~160pt wide, ~100pt tall (aspect ratio preserved)

### Custom Wallpaper

`NSOpenPanel` configured for image files (png, jpg, jpeg, webp). Since the app uses direct distribution (not sandboxed), the selected file path can be stored directly in `AppStore.backgroundImage` and accessed at runtime. Note: if sandboxing is added later, security-scoped bookmarks would be needed instead of raw paths.

## Transparency

### How It Works

When `backgroundImage` is set (not nil):

1. **Wallpaper layer**: An `Image` fills the entire Shell area behind all content, with optional blur applied
2. **Sidebar**: background changes from `theme.bg2` to `theme.bg2.opacity(backgroundOpacity)`
3. **Tab bar**: background changes from `theme.bg2` to `theme.bg2.opacity(backgroundOpacity)`
4. **Status line**: background changes from `theme.bg` to `theme.bg.opacity(backgroundOpacity)`
5. **Content area**: gets a tint overlay of `theme.bg.opacity(backgroundOpacity)` so terminal content (future) remains readable

When `backgroundImage` is nil, all backgrounds are fully opaque (current behavior).

### Wallpaper Rendering

```
Shell ZStack:
  ├── Wallpaper image (fills entire window, .resizable().aspectRatio(contentMode: .fill))
  │   └── .scaleEffect(1.1) to prevent visible edges when blurred
  │   └── .blur(radius: backgroundBlur) if blur > 0
  │   └── .clipped() to crop overflow
  └── VStack (existing layout)
       ├── TabBar (semi-transparent bg)
       ├── HStack
       │    ├── Sidebar (semi-transparent bg)
       │    ├── Border
       │    └── Content (tinted overlay) + StatusLine
       └── ...
```

### Controls

**Background opacity:**
- Slider: range 0.1 to 1.0, step 0.05
- Label: shows percentage (e.g., "95%")
- Default: 0.75
- Only enabled when a wallpaper is active

**Background blur:**
- Slider: range 0 to 32, step 1
- Label: shows value in px (e.g., "8px")
- Default: 0
- Only enabled when a wallpaper is active

**Hide titlebar:**
- Toggle switch
- Non-functional in this milestone (needs AppKit `NSWindow` style mask changes)
- Present but disabled with a note

## State Changes

### AppStore Additions

```swift
// New properties:
var activeView: ActiveView = .projects  // .projects | .settings
var backgroundImage: String?            // "preset:xxx" for bundled, file path for custom
var backgroundOpacity: Double = 0.75    // 0.1...1.0
var backgroundBlur: Double = 0          // 0...32

enum ActiveView {
    case projects
    case settings
}
```

Add setter methods for each property. The `backgroundImage` value uses `preset:` prefix for bundled wallpapers (e.g., `"preset:ship-at-sea"`) and raw file paths for custom images, matching Krux's convention.

### ThemeManager Changes

Add a static registry and switching method:

```swift
static let allThemes: [Theme] = [.cyberpunk, .josean, .dracula, ...]

func setTheme(id: String) {
    if let theme = Self.allThemes.first(where: { $0.id == id }) {
        activeTheme = theme
    }
}
```

## Files

| File | Action | What |
|------|--------|------|
| `Blink/Theme/Theme.swift` | Modify | Add 10 remaining theme presets |
| `Blink/Theme/ThemeManager.swift` | Modify | Add `allThemes` registry and `setTheme(id:)` |
| `Blink/Store/AppStore.swift` | Modify | Add background properties + setters |
| `Blink/Views/SettingsPage.swift` | Create | Full overlay with tab sidebar |
| `Blink/Views/Settings/AppearanceSettings.swift` | Create | Theme grid, wallpaper grid, sliders |
| `Blink/Views/Settings/ThemeCard.swift` | Create | Individual theme picker card |
| `Blink/Views/Settings/WallpaperCard.swift` | Create | Wallpaper thumbnail card |
| `Blink/Models/WallpaperPreset.swift` | Create | Wallpaper preset data model |
| `Blink/Views/Shell.swift` | Modify | Add wallpaper ZStack layer, wire transparency |
| `Blink/Views/Sidebar.swift` | Modify | Conditional transparent background |
| `Blink/Views/TabBar.swift` | Modify | Conditional transparent background |
| `Blink/Views/StatusLine.swift` | Modify | Conditional transparent background |
| Resources/ | Add | 8 wallpaper image files |

## What's NOT in This Milestone

- Settings persistence to disk (~/.blink/settings.json)
- Terminal settings tab
- Keyboard shortcuts tab
- Hide titlebar functionality (toggle present but disabled)
- Wallpaper switcher modal (Ctrl+A chord — deferred to keyboard navigation milestone)
- Theme switcher modal (Ctrl+A chord)
- Background adjuster overlay (Ctrl+A chord)
