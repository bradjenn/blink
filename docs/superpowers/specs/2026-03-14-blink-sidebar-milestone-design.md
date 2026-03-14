# Blink — Milestone 1: Sidebar Visual Parity

## Overview

Rebuild the Krux terminal multiplexer (`~/Code/krux`) as a native macOS app using Swift/SwiftUI. This first milestone proves that the sidebar, tab bar, and status line can achieve pixel-perfect visual parity with the existing Electron/React app before investing in terminal integration (libghostty) or backend functionality.

**Success criteria:** Open the app, see the Krux layout with Cyberpunk theme, interact with project items (click, hover, selection state, pulse animation), and confirm it is visually indistinguishable from the Electron version.

## Architecture

### Tech Stack

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI (sidebar, tabs, overlays, settings, chat, project UI)
- **Terminal (future):** libghostty via AppKit bridge
- **Target:** macOS 14+ (Sonoma), direct distribution (no App Store sandbox)
- **Build:** Xcode project, Swift Package Manager for dependencies

### Architecture Split (Future-Proof)

- **SwiftUI** for all declarative UI: sidebar, tab bar, status line, overlays, settings, chat
- **AppKit bridge** (future) for terminal container and keyboard/focus plumbing
- This milestone is 100% SwiftUI — no AppKit needed yet

### Project Structure

```
Blink/
├── BApp.swift                    # @main App entry, WindowGroup
├── Theme/
│   ├── Theme.swift               # Theme struct + Cyberpunk preset
│   ├── ThemeManager.swift        # @Observable, publishes active theme
│   └── Color+Hex.swift           # Color(hex:) initializer
├── Models/
│   ├── Project.swift             # Project model
│   └── Tab.swift                 # Tab model
├── Store/
│   └── AppStore.swift            # Central @Observable state
├── Views/
│   ├── Shell.swift               # Root layout orchestrator
│   ├── Sidebar.swift             # Project list
│   ├── SidebarProjectItem.swift  # Individual project row
│   ├── TabBar.swift              # Tab bar with logo area
│   ├── StatusLine.swift          # Bottom status bar
│   ├── ProjectFavicon.swift      # Project icon (folder fallback)
│   └── StartScreen.swift         # Empty state placeholder
└── Utilities/
    └── Constants.swift           # Layout constants
```

## Theme System

### Theme Struct

Mirrors Krux's `ThemePreset.ui` exactly:

```swift
struct Theme {
    let name: String
    let bg: Color        // Main background
    let bg2: Color       // Surface/sidebar background
    let border: Color    // Border color
    let accent: Color    // Primary accent
    let accent2: Color   // Secondary accent
    let text: Color      // Primary text
    let textMuted: Color // Muted text
    let textDim: Color   // Dim text
    let danger: Color    // Destructive/error
    let green: Color     // Success
    let yellow: Color    // Warning
    let magenta: Color   // Purple accent

    // Computed
    var accentGlow: Color       // accent at 20% opacity
    var accentGlowStrong: Color  // accent at 35% opacity
    var accent2Glow: Color       // accent2 at 20% opacity
}
```

### Cyberpunk Theme (Default, internal key: "ghostty")

| Token | Hex Value |
|-------|-----------|
| bg | `#080810` |
| bg2 | `#0c1018` |
| border | `#1e2d40` |
| accent | `#c8ff00` |
| accent2 | `#0fc5ed` |
| text | `#d0e0f0` |
| textMuted | `#7a9ab8` |
| textDim | `#4a6580` |
| danger | `#ff2e4a` |
| green | `#44ffb1` |
| yellow | `#ffe073` |
| magenta | `#a277ff` |

### ThemeManager

- `@Observable` class injected into SwiftUI environment
- `activeTheme` property drives all UI colors
- Changing the theme recolors the entire app instantly
- Adding themes later = adding static `Theme` instances (copy hex values from `themes.ts`)

## App State (AppStore)

Single `@Observable` class mirroring Krux's Zustand store:

```
AppStore
  ├── projects: [Project]          // id, name, path, color, createdAt
  ├── activeProjectId: String?
  ├── tabs: [Tab]                  // id, type, label, projectId, terminalId?
  ├── activeTabId: String?
  ├── theme: String                // "ghostty" default
  ├── sidebarVisible: Bool         // true default, no toggle mechanism in M1 (always visible)
  └── (terminal settings stubbed for later)
```

### Project Model

```swift
struct Project: Identifiable {
    let id: String           // UUID
    let name: String         // Display name
    let path: String         // Absolute path
    let color: String        // Hex color
    let createdAt: Date
}
```

### Tab Model

```swift
struct Tab: Identifiable {
    let id: String           // UUID
    let type: String         // "shell", "tool:claude-code", etc.
    let label: String        // Display label
    let projectId: String
    var terminalId: String?  // Only for shell tabs
}
```

### Data for Milestone 1

Hardcoded dummy projects (no filesystem scanning):

```swift
static let dummy: [Project] = [
    Project(id: "1", name: "blink", path: "/Users/bradley/Code/blink", ...),
    Project(id: "2", name: "krux", path: "/Users/bradley/Code/krux", ...),
    Project(id: "3", name: "api-server", path: "/Users/bradley/Code/api-server", ...),
]
```

Each project gets 1-2 dummy tabs to test the tab bar and terminal count badge.

## Layout Specification

### Window

- Minimum size: 800 x 500
- Default size: 1200 x 750
- Background: `#080810`
- Standard macOS title bar (hideable later)
- Force dark appearance (`.preferredColorScheme(.dark)` or `NSApp.appearance = NSAppearance(named: .darkAqua)`) to prevent light-mode title bar mismatch

### Layout Tree

```
Window (#080810 background)
 └── VStack(spacing: 0)
      ├── TabBar ─────────────────────────── 36pt height, full width
      │    ├── Logo area ────────────────── width matches sidebar, border-right
      │    │    └── "KRUX" label ─────────── 11pt, bold, tracking 0.15em, textDim
      │    ├── Tab pills ────────────────── scrollable horizontal
      │    │    └── per tab ──────────────── 14pt h-padding, 12px font
      │    └── + button ─────────────────── 36pt square, textDim
      │
      ├── HStack(spacing: 0) ──────────── flex-1
      │    ├── Sidebar ──────────────────── 340pt width, border-right
      │    │    ├── Header ──────────────── "PROJECTS" 11pt font-medium uppercase + add btn
      │    │    │    padding: 16pt left, 12pt top, 8pt bottom
      │    │    │    Add button: 18pt note-add icon, strokeWidth 1.5
      │    │    │    color textMuted, hover → text, non-functional in M1
      │    │    ├── ScrollView ──────────── flex-1, project items
      │    │    │    └── ProjectItem ─────── see below
      │    │    └── Footer
      │    │         └── Settings button ── 32pt height, 14pt icon
      │    │
      │    └── VStack(spacing: 0) ──────── flex-1
      │         ├── Content area ────────── flex-1 (placeholder)
      │         └── StatusLine ──────────── 32pt height, border-top
      └── (end)
```

### Sidebar Project Item

Each project row, pixel-matched to Krux's `Sidebar.tsx`:

```
┌─────────────────────────────────────────┐
│ ┃  [icon]  Project Name            ● 2  │
│ ┃          ~/Code/project-name     [×]  │
└─────────────────────────────────────────┘
 ↑              ↑            ↑         ↑
 3pt border     15pt name    pulse     remove (hover only)
 (accent if     13pt path    dot       13pt icon
  active)       textDim      accent
```

**Padding:** 8pt top, 12pt right, 8pt bottom, 10pt left
**Left border:** 3pt wide — accent color when active, transparent when inactive
**Active background:** accent at 4% opacity
**Hover background:** accent2 (`#0fc5ed`) at 4% opacity (inactive items only)
**Icon:** 15pt, folder icon fallback (ProjectFavicon)
**Name:** 15pt, font-medium, truncated
**Path:** 13pt, textDim, truncated, 1pt top margin, `~` substitution for home dir
**Terminal count:** 12pt, accent color, with animated pulse dot
**Pulse dot:** 6pt circle, accent color, shadow `0 0 4pt accentGlow`, 2s ease-in-out infinite animation (opacity 1 → 0.4 → 1)
**Terminal count number:** Only displayed when count >= 2. With exactly 1 terminal, show only the pulse dot (no number).
**Remove button:** 13pt delete icon, opacity 0, transitions to opacity 1 on row hover, textDim → danger on hover
**Gap between icon and text:** 10pt (gap-2.5)

### Sidebar Vim Selection Overlay (Milestone 2)

Deferred to Milestone 2 (keyboard navigation). When implemented:
- Background: `rgba(255, 255, 255, 0.06)`
- Outline: 1pt solid accent2, -1pt offset
- Vim hint bar in footer: `j/k nav  Enter select  Esc back`

### Sidebar Footer

**Settings button:**
- Height: 32pt
- Full width, border-top
- 14pt gear icon + "Settings" label at 12.5pt
- Color: textDim, hover → text

### Tab Bar

**Container:** 36pt height, border-bottom, scrollable overflow-x

**Logo area:**
- Width: 340pt (matches sidebar, animates with sidebar toggle)
- Padding-left: 78pt (accounts for macOS traffic lights)
- "KRUX" text: 11pt, bold, tracking 0.15em, uppercase, textDim
- Border-right

**Tab pills:**
- Height: 100%
- Padding: 0 14pt horizontal
- Font: 12pt
- Active: text color, 2pt bottom border accent, white/2% bg
- Inactive: textMuted, transparent bottom border
- Hover: text color, white/2% bg
- Close button: 11pt × icon, opacity 0 → 1 on tab hover, danger color on hover

**Plus button:**
- 36pt × 36pt
- textDim, hover → accent

### Status Line

**Container:** 32pt height, border-top, 14pt horizontal padding, bg color

**Left section:**
- Mode badge (only in prefix mode): "PREFIX" label, 11pt bold, bg yellow, text bg color, rounded-sm, 1.5pt horizontal padding
- Update status placeholder (stubbed)

**Center section:**
- Project name: textMuted, truncated, 16pt horizontal padding

**Right section:**
- Git status placeholder: branch icon (10pt) + branch name in textMuted + colored diff counts (green +N, yellow ~N, danger -N)
- Terminal count: "N terms" in textMuted

### Start Screen

Simple centered content when no project is selected:
- Folder icon (48pt, textDim at 50% opacity)
- "No project selected" heading
- Subtle hint text

## Interactions & Animations

| Interaction | Behavior |
|------------|----------|
| Click project | Sets `activeProjectId`, updates sidebar highlight + tab bar + status line |
| Hover project (inactive) | 4% accent2 background overlay |
| Hover project | Remove button fades in (100ms) |
| Hover remove button | Color transitions textDim → danger (100ms) |
| Click remove button | Removes from dummy list (no persistence yet) |
| Terminal count dot | Pulses opacity 1→0.4→1 on 2s ease-in-out loop |
| Sidebar toggle | 200ms ease-in-out slide via negative margin |
| Tab click | Sets `activeTabId` |
| Tab hover | Close button fades in |
| Tab close hover | Text goes danger, bg goes danger/15% |

## Fonts

**Primary:** JetBrains Mono (must be installed on system)
**Fallback chain:** "JetBrains Mono", "SF Mono", "Fira Code", .monospaced (system)

The app uses monospace everywhere, matching Krux's terminal aesthetic. In SwiftUI, use `Font.custom("JetBrains Mono", size: N)` with `.monospaced` as the system fallback.

## SwiftUI Implementation Notes

These notes help bridge CSS/React concepts to SwiftUI equivalents:

- **Hover states:** Use `@State private var isHovered = false` + `.onHover { isHovered = $0 }` modifier (macOS only)
- **Sidebar slide animation:** Use `.offset(x: sidebarVisible ? 0 : -340)` with `.animation(.easeInOut(duration: 0.2), value: sidebarVisible)` — the CSS negative-margin trick doesn't apply in SwiftUI
- **`@Observable` vs `@ObservableObject`:** This project uses `@Observable` (Swift 5.9 Observation macro, macOS 14+), NOT the older Combine-based `@ObservableObject`. Views automatically track property access without `@Published` wrappers
- **`Color(hex:)`:** SwiftUI has no built-in hex color initializer. We create a `Color` extension that parses hex strings — this is the foundation of the theme system
- **`Project.color`:** Present in the model for future use (project-specific accent colors). Not rendered in Milestone 1
- **`Project.createdAt`:** Uses Swift-native `Date` type (intentional improvement over Krux's string-based `created_at`)

## What's NOT in Milestone 1

- Terminal emulation (libghostty)
- Filesystem project discovery
- Settings persistence (~/.blink/)
- Keyboard navigation (Ctrl+A prefix mode, vim sidebar)
- Chat panel
- GSD workflow viewer
- Wallpapers and background effects
- Theme switching UI
- Project switcher modal (Cmd+P fuzzy search)
- WhichKey overlay
- Notifications toast system
- Auto-update system
- Native macOS menu bar items
- Drag-and-drop

## Future Milestones (Not Designed Yet)

1. **Milestone 2:** Keyboard navigation (Ctrl+A prefix, vim sidebar, WhichKey)
2. **Milestone 3:** libghostty terminal integration
3. **Milestone 4:** Project discovery + persistence
4. **Milestone 5:** Theme switching + wallpapers
5. **Milestone 6:** Chat panel + AI tool tabs
6. **Milestone 7:** GSD workflow viewer
7. **Milestone 8:** Auto-update + distribution
