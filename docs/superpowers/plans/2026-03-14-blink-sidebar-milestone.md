# Blink Milestone 1: Sidebar Visual Parity — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS SwiftUI app that displays Krux's sidebar, tab bar, and status line with pixel-perfect visual parity using the Cyberpunk theme and hardcoded dummy data.

**Architecture:** Pure SwiftUI app targeting macOS 14+. Single `@Observable` AppStore drives all state. Theme system uses a `Theme` struct with hex color tokens injected via SwiftUI environment. Views mirror Krux's React component hierarchy 1:1.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 14+ (Sonoma), XcodeGen for project generation

**Spec:** `docs/superpowers/specs/2026-03-14-blink-sidebar-milestone-design.md`

---

## File Map

| File | Responsibility |
|------|---------------|
| `project.yml` | XcodeGen project definition |
| `Blink/BApp.swift` | `@main` App entry, WindowGroup, environment injection |
| `Blink/Theme/Color+Hex.swift` | `Color(hex:)` initializer extension |
| `Blink/Theme/Theme.swift` | Theme struct, Cyberpunk preset, all color tokens |
| `Blink/Theme/ThemeManager.swift` | `@Observable` theme publisher, environment key |
| `Blink/Models/Project.swift` | Project model + dummy data |
| `Blink/Models/Tab.swift` | Tab model |
| `Blink/Store/AppStore.swift` | Central `@Observable` state (projects, tabs, active IDs) |
| `Blink/Utilities/Constants.swift` | Layout constants (widths, heights, padding) |
| `Blink/Views/Shell.swift` | Root layout: VStack(TabBar + HStack(Sidebar + Content + StatusLine)) |
| `Blink/Views/Sidebar.swift` | Project list container with header, scroll, footer |
| `Blink/Views/SidebarProjectItem.swift` | Individual project row with all visual states |
| `Blink/Views/ProjectFavicon.swift` | Folder icon (15pt, system SF Symbol) |
| `Blink/Views/TabBar.swift` | Tab bar with KRUX logo, tab pills, + button |
| `Blink/Views/StatusLine.swift` | Bottom bar: mode badge, project name, git placeholder |
| `Blink/Views/StartScreen.swift` | "No project selected" empty state |
| `BTests/ColorHexTests.swift` | Tests for hex color parsing |
| `BTests/AppStoreTests.swift` | Tests for state mutations |

---

## Chunk 1: Project Scaffold + Theme Foundation

### Task 1: Create Xcode project with XcodeGen

XcodeGen generates `.xcodeproj` from a YAML spec, avoiding hand-crafted project files.

**Files:**
- Create: `project.yml`
- Create: `Blink/BApp.swift` (minimal placeholder)
- Create: `BTests/ColorHexTests.swift` (minimal placeholder)

- [ ] **Step 1: Install XcodeGen if not present**

```bash
brew list xcodegen 2>/dev/null || brew install xcodegen
```

- [ ] **Step 2: Create .gitignore**

```
# Xcode
*.xcodeproj/xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/
DerivedData/
build/
*.swp
.DS_Store
```

- [ ] **Step 3: Create project.yml**

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
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.blink.app
        INFOPLIST_KEY_CFBundleDisplayName: Blink
        GENERATE_INFOPLIST_FILE: true
        PRODUCT_NAME: Blink
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

- [ ] **Step 4: Create directory structure and minimal entry point**

```bash
mkdir -p Blink/Theme Blink/Models Blink/Store Blink/Views Blink/Utilities BTests
```

Create `Blink/BApp.swift`:

```swift
import SwiftUI

@main
struct BApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Blink")
                .frame(minWidth: 800, minHeight: 500)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1200, height: 750)
    }
}
```

Create `BTests/ColorHexTests.swift`:

```swift
import XCTest
@testable import Blink

final class ColorHexTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 5: Generate Xcode project and verify it builds**

```bash
xcodegen generate
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add .gitignore project.yml Blink/ BTests/ Blink.xcodeproj/
git commit -m "scaffold: Xcode project with XcodeGen, minimal SwiftUI app entry"
```

---

### Task 2: Color+Hex extension

Foundation of the theme system. Parses hex strings like `#080810` into SwiftUI `Color`.

**Files:**
- Create: `Blink/Theme/Color+Hex.swift`
- Modify: `BTests/ColorHexTests.swift`

- [ ] **Step 1: Write failing tests**

Replace `BTests/ColorHexTests.swift`:

```swift
import XCTest
@testable import Blink

final class ColorHexTests: XCTestCase {
    func testParsesSixDigitHex() {
        // #080810 -> r: 8/255, g: 8/255, b: 16/255
        let components = Color.hexComponents("#080810")
        XCTAssertNotNil(components)
        XCTAssertEqual(components!.red, 8.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(components!.green, 8.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(components!.blue, 16.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(components!.alpha, 1.0)
    }

    func testParsesWithoutHash() {
        let components = Color.hexComponents("c8ff00")
        XCTAssertNotNil(components)
        XCTAssertEqual(components!.red, 200.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(components!.green, 1.0, accuracy: 0.001)
        XCTAssertEqual(components!.blue, 0.0, accuracy: 0.001)
    }

    func testReturnsNilForInvalidHex() {
        XCTAssertNil(Color.hexComponents("xyz"))
        XCTAssertNil(Color.hexComponents("#12"))
        XCTAssertNil(Color.hexComponents(""))
    }

    func testColorInitializerDoesNotCrash() {
        // Smoke test — can't easily inspect Color internals
        let color = Color(hex: "#0fc5ed")
        XCTAssertNotNil(color)
    }

    func testWithAlpha() {
        let color = Color(hex: "#c8ff00", opacity: 0.2)
        XCTAssertNotNil(color)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: FAIL — `hexComponents` and `Color(hex:)` not defined.

- [ ] **Step 3: Implement Color+Hex**

Create `Blink/Theme/Color+Hex.swift`:

```swift
import SwiftUI

extension Color {
    /// Parse hex string into RGBA components. Accepts "#RRGGBB" or "RRGGBB".
    static func hexComponents(_ hex: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&rgb) else { return nil }
        return (
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    /// Create a Color from a hex string. Falls back to clear if parsing fails.
    init(hex: String, opacity: Double = 1.0) {
        if let c = Color.hexComponents(hex) {
            self = Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: opacity)
        } else {
            #if DEBUG
            print("⚠️ Invalid hex color: \(hex)")
            #endif
            self = Color.clear
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: All 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Blink/Theme/Color+Hex.swift BTests/ColorHexTests.swift
git commit -m "feat: add Color(hex:) extension with tests"
```

---

### Task 3: Theme struct + Cyberpunk preset

**Files:**
- Create: `Blink/Theme/Theme.swift`

- [ ] **Step 1: Create Theme struct with Cyberpunk preset**

```swift
import SwiftUI

struct Theme {
    let id: String
    let name: String

    // UI color tokens — exact hex values from Krux's themes.ts
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

extension Theme {
    /// Cyberpunk theme — internal key "ghostty", matches Krux default.
    static let cyberpunk = Theme(
        id: "ghostty",
        name: "Cyberpunk",
        bg: Color(hex: "#080810"),
        bg2: Color(hex: "#0c1018"),
        border: Color(hex: "#1e2d40"),
        accent: Color(hex: "#c8ff00"),
        accent2: Color(hex: "#0fc5ed"),
        text: Color(hex: "#d0e0f0"),
        textMuted: Color(hex: "#7a9ab8"),
        textDim: Color(hex: "#4a6580"),
        danger: Color(hex: "#ff2e4a"),
        green: Color(hex: "#44ffb1"),
        yellow: Color(hex: "#ffe073"),
        magenta: Color(hex: "#a277ff")
    )
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Blink/Theme/Theme.swift
git commit -m "feat: add Theme struct with Cyberpunk preset"
```

---

### Task 4: ThemeManager + environment injection

**Files:**
- Create: `Blink/Theme/ThemeManager.swift`

- [ ] **Step 1: Create ThemeManager**

```swift
import SwiftUI

@Observable
final class ThemeManager {
    var activeTheme: Theme = .cyberpunk
}

// SwiftUI Environment key for the active theme
private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: Theme = .cyberpunk
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Blink/Theme/ThemeManager.swift
git commit -m "feat: add ThemeManager with environment key for theme injection"
```

---

## Chunk 2: Models, State, and Constants

### Task 5: Project and Tab models

**Files:**
- Create: `Blink/Models/Project.swift`
- Create: `Blink/Models/Tab.swift`

- [ ] **Step 1: Create Project model with dummy data**

```swift
import Foundation

struct Project: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let path: String
    let color: String     // Hex color, reserved for future use
    let createdAt: Date

    /// Home directory path prefix replacement for display.
    var displayPath: String {
        path.replacingOccurrences(
            of: "/Users/\(NSUserName())",
            with: "~"
        )
    }
}

extension Project {
    static let dummy: [Project] = [
        Project(id: "1", name: "blink", path: "/Users/bradley/Code/blink", color: "#c8ff00", createdAt: Date()),
        Project(id: "2", name: "krux", path: "/Users/bradley/Code/krux", color: "#0fc5ed", createdAt: Date()),
        Project(id: "3", name: "api-server", path: "/Users/bradley/Code/api-server", color: "#a277ff", createdAt: Date()),
        Project(id: "4", name: "dotfiles", path: "/Users/bradley/Code/dotfiles", color: "#44ffb1", createdAt: Date()),
    ]
}
```

- [ ] **Step 2: Create Tab model with dummy data**

```swift
import Foundation

struct Tab: Identifiable, Equatable, Hashable {
    let id: String
    let type: String         // "shell", "tool:claude-code", etc.
    let label: String
    let projectId: String
    var terminalId: String?  // Only for shell tabs
}

extension Tab {
    /// Dummy tabs for testing — 2 for first project, 1 for second, 0 for rest.
    static let dummy: [Tab] = [
        Tab(id: "t1", type: "shell", label: "Terminal 1", projectId: "1", terminalId: "pty-1"),
        Tab(id: "t2", type: "shell", label: "Terminal 2", projectId: "1", terminalId: "pty-2"),
        Tab(id: "t3", type: "shell", label: "Terminal 1", projectId: "2", terminalId: "pty-3"),
    ]
}
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Blink/Models/
git commit -m "feat: add Project and Tab models with dummy data"
```

---

### Task 6: AppStore

**Files:**
- Create: `Blink/Store/AppStore.swift`
- Create: `BTests/AppStoreTests.swift`

- [ ] **Step 1: Write failing tests for AppStore**

```swift
import XCTest
@testable import Blink

final class AppStoreTests: XCTestCase {
    func testInitialState() {
        let store = AppStore()
        XCTAssertEqual(store.projects.count, 4)
        XCTAssertNil(store.activeProjectId)
        XCTAssertNil(store.activeTabId)
        XCTAssertTrue(store.sidebarVisible)
    }

    func testSetActiveProjectActivatesFirstTab() {
        let store = AppStore()
        store.setActiveProject("1") // has 2 tabs
        XCTAssertEqual(store.activeProjectId, "1")
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testSetActiveProjectNoTabs() {
        let store = AppStore()
        store.setActiveProject("4") // dotfiles — no tabs
        XCTAssertEqual(store.activeProjectId, "4")
        XCTAssertNil(store.activeTabId)
    }

    func testClearActiveProject() {
        let store = AppStore()
        store.setActiveProject("1")
        store.setActiveProject(nil)
        XCTAssertNil(store.activeProjectId)
        XCTAssertNil(store.activeTabId)
    }

    func testProjectTabs() {
        let store = AppStore()
        let tabs = store.projectTabs(for: "1")
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0].label, "Terminal 1")
    }

    func testRemoveProject() {
        let store = AppStore()
        store.removeProject("1")
        XCTAssertEqual(store.projects.count, 3)
        XCTAssertFalse(store.projects.contains(where: { $0.id == "1" }))
    }

    func testRemoveActiveProjectClearsSelection() {
        let store = AppStore()
        store.setActiveProject("1")
        store.removeProject("1")
        XCTAssertNil(store.activeProjectId)
        XCTAssertNil(store.activeTabId)
    }

    func testTerminalCount() {
        let store = AppStore()
        XCTAssertEqual(store.terminalCount(for: "1"), 2)
        XCTAssertEqual(store.terminalCount(for: "2"), 1)
        XCTAssertEqual(store.terminalCount(for: "4"), 0)
    }

    func testSetActiveTab() {
        let store = AppStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")
        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testCloseTab() {
        let store = AppStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.closeTab("t1")
        // Should activate last remaining tab in same project
        XCTAssertEqual(store.activeTabId, "t2")
        XCTAssertEqual(store.tabs.count, 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: FAIL — `AppStore` not defined.

- [ ] **Step 3: Implement AppStore**

```swift
import SwiftUI

@Observable
final class AppStore {
    // Projects
    var projects: [Project] = Project.dummy
    var activeProjectId: String?

    // Tabs
    var tabs: [Tab] = Tab.dummy
    var activeTabId: String?

    // Theme
    var theme: String = "ghostty"

    // Sidebar
    var sidebarVisible: Bool = true

    // MARK: - Actions

    func setActiveProject(_ id: String?) {
        activeProjectId = id
        if let id {
            let projectTabs = projectTabs(for: id)
            activeTabId = projectTabs.first?.id
        } else {
            activeTabId = nil
        }
    }

    func setActiveTab(_ id: String) {
        activeTabId = id
    }

    func projectTabs(for projectId: String) -> [Tab] {
        tabs.filter { $0.projectId == projectId }
    }

    func terminalCount(for projectId: String) -> Int {
        tabs.filter { $0.projectId == projectId && $0.type == "shell" }.count
    }

    func removeProject(_ id: String) {
        projects.removeAll { $0.id == id }
        tabs.removeAll { $0.projectId == id }
        if activeProjectId == id {
            activeProjectId = nil
            activeTabId = nil
        }
    }

    func closeTab(_ id: String) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tabs.removeAll { $0.id == id }
        if activeTabId == id {
            let remaining = projectTabs(for: tab.projectId)
            activeTabId = remaining.last?.id
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: All 10 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Blink/Store/AppStore.swift BTests/AppStoreTests.swift
git commit -m "feat: add AppStore with project/tab state management and tests"
```

---

### Task 7: Layout constants

**Files:**
- Create: `Blink/Utilities/Constants.swift`

- [ ] **Step 1: Create constants file**

All magic numbers from the spec in one place.

```swift
import Foundation

enum Layout {
    // Sidebar
    static let sidebarWidth: CGFloat = 340
    static let sidebarItemPadding = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 12)
    static let sidebarItemBorderWidth: CGFloat = 3
    static let sidebarItemGap: CGFloat = 10        // gap-2.5
    static let sidebarHeaderPadding = EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16)
    static let sidebarSettingsHeight: CGFloat = 32

    // Tab bar
    static let tabBarHeight: CGFloat = 36
    static let tabBarLogoPaddingLeft: CGFloat = 78 // macOS traffic lights offset
    static let tabPillPaddingH: CGFloat = 14

    // Status line
    static let statusLineHeight: CGFloat = 32
    static let statusLinePaddingH: CGFloat = 14

    // Window
    static let windowMinWidth: CGFloat = 800
    static let windowMinHeight: CGFloat = 500
    static let windowDefaultWidth: CGFloat = 1200
    static let windowDefaultHeight: CGFloat = 750
}

enum Fonts {
    /// Returns the correct JetBrains Mono variant name for a given weight.
    /// SwiftUI's `.weight()` does NOT work with custom fonts — you must use the
    /// exact PostScript font name for each weight variant.
    static func primary(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold:
            name = "JetBrainsMono-Bold"
        case .medium:
            name = "JetBrainsMono-Medium"
        case .semibold:
            name = "JetBrainsMono-SemiBold"
        case .light:
            name = "JetBrainsMono-Light"
        default:
            name = "JetBrainsMono-Regular"
        }
        // If the custom font isn't installed, SwiftUI falls back to system font.
        // The app should bundle the font or require it installed (see BApp.swift).
        return .custom(name, size: size)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Blink/Utilities/Constants.swift
git commit -m "feat: add layout constants and font helpers"
```

---

## Chunk 3: Shell Layout + Simple Views

### Task 8: Shell root layout

The main orchestrator view. Mirrors Krux's `Shell.tsx` layout tree.

**Files:**
- Create: `Blink/Views/Shell.swift`
- Modify: `Blink/BApp.swift`

- [ ] **Step 1: Create Shell.swift with layout structure**

```swift
import SwiftUI

struct Shell: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — full width, 36pt
            TabBar()
                .frame(height: Layout.tabBarHeight)

            // Body: sidebar + content
            HStack(spacing: 0) {
                // Sidebar — 340pt, border-right
                Sidebar()
                    .frame(width: Layout.sidebarWidth)

                // Content + status line
                VStack(spacing: 0) {
                    // Content area
                    ZStack {
                        theme.bg
                        if store.activeProjectId == nil {
                            StartScreen()
                        } else {
                            // Placeholder for terminal content
                            theme.bg
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Status line — 32pt
                    StatusLine()
                        .frame(height: Layout.statusLineHeight)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(theme.bg)
        .font(Fonts.primary(size: 13))
    }
}
```

- [ ] **Step 2: Update BApp.swift to wire everything together**

```swift
import SwiftUI

@main
struct BApp: App {
    @State private var themeManager = ThemeManager()
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            Shell()
                .environment(store)
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

- [ ] **Step 3: Create placeholder stubs for views not yet built**

These are temporary stubs so the project compiles. Each will be replaced in subsequent tasks.

Create `Blink/Views/TabBar.swift`:

```swift
import SwiftUI

struct TabBar: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Text("KRUX")
                .font(Fonts.primary(size: 11, weight: .bold))
                .foregroundStyle(theme.textDim)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(theme.bg2)
        .overlay(alignment: .bottom) {
            theme.border.frame(height: 1)
        }
    }
}
```

Create `Blink/Views/Sidebar.swift`:

```swift
import SwiftUI

struct Sidebar: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack {
            Text("PROJECTS")
                .font(Fonts.primary(size: 11, weight: .medium))
                .foregroundStyle(theme.textDim)
            Spacer()
        }
        .frame(maxHeight: .infinity)
        .background(theme.bg2)
        .overlay(alignment: .trailing) {
            theme.border.frame(width: 1)
        }
    }
}
```

Create `Blink/Views/StatusLine.swift`:

```swift
import SwiftUI

struct StatusLine: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(theme.bg)
        .overlay(alignment: .top) {
            theme.border.frame(height: 1)
        }
    }
}
```

Create `Blink/Views/StartScreen.swift`:

```swift
import SwiftUI

struct StartScreen: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(theme.textDim.opacity(0.5))
            Text("No project selected")
                .font(Fonts.primary(size: 16))
                .foregroundStyle(theme.textMuted)
            Text("Select a project from the sidebar")
                .font(Fonts.primary(size: 13))
                .foregroundStyle(theme.textDim)
        }
    }
}
```

- [ ] **Step 4: Build and run to verify window appears**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED. Running the app should show a dark window with "KRUX" top-left, "PROJECTS" in the sidebar area, and "No project selected" in the center.

- [ ] **Step 5: Commit**

```bash
git add Blink/Views/ Blink/BApp.swift
git commit -m "feat: add Shell layout with placeholder views"
```

---

### Task 9: StatusLine (full implementation)

**Files:**
- Modify: `Blink/Views/StatusLine.swift`

- [ ] **Step 1: Replace StatusLine.swift with full implementation**

```swift
import SwiftUI

struct StatusLine: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    private var activeProject: Project? {
        store.projects.first { $0.id == store.activeProjectId }
    }

    private var terminalCount: Int {
        guard let id = store.activeProjectId else { return 0 }
        return store.terminalCount(for: id)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: mode indicator (placeholder — always terminal mode in M1)
            HStack(spacing: 8) {
                // Mode badge would go here in M2
            }
            .frame(minWidth: 0)

            // Center: project name
            if let project = activeProject {
                Text(project.name)
                    .font(Fonts.primary(size: 12))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
            } else {
                Spacer()
            }

            // Right: git placeholder + terminal count
            if store.activeProjectId != nil {
                HStack(spacing: 12) {
                    // Git status placeholder
                    HStack(spacing: 6) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textMuted)
                        Text("main")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.textMuted)
                        Text("+2")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.green)
                        Text("~1")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.yellow)
                        Text("-1")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.danger)
                    }

                    if terminalCount > 0 {
                        Text("\(terminalCount) term\(terminalCount != 1 ? "s" : "")")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.textMuted)
                    }
                }
            }
        }
        .padding(.horizontal, Layout.statusLinePaddingH)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
        .overlay(alignment: .top) {
            theme.border.frame(height: 1)
        }
        .font(Fonts.primary(size: 12))
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Blink/Views/StatusLine.swift
git commit -m "feat: implement StatusLine with project name, git placeholder, terminal count"
```

---

## Chunk 4: Sidebar (The Critical Piece)

### Task 10: ProjectFavicon

**Files:**
- Create: `Blink/Views/ProjectFavicon.swift`

- [ ] **Step 1: Create ProjectFavicon**

Simple folder icon for now. Future milestones will load actual favicons from project directories.

```swift
import SwiftUI

struct ProjectFavicon: View {
    @Environment(\.theme) private var theme
    let size: CGFloat

    init(size: CGFloat = 15) {
        self.size = size
    }

    var body: some View {
        Image(systemName: "folder")
            .font(.system(size: size, weight: .light))
            .foregroundStyle(theme.textMuted)
            .frame(width: size, height: size)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Blink/Views/ProjectFavicon.swift
git commit -m "feat: add ProjectFavicon with folder icon fallback"
```

---

### Task 11: SidebarProjectItem

The most visually critical component. Must match Krux's `Sidebar.tsx` project rows exactly.

**Files:**
- Create: `Blink/Views/SidebarProjectItem.swift`

- [ ] **Step 1: Create SidebarProjectItem with all visual states**

```swift
import SwiftUI

struct SidebarProjectItem: View {
    @Environment(\.theme) private var theme

    let project: Project
    let isActive: Bool
    let terminalCount: Int
    let onSelect: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false
    @State private var isRemoveHovered = false

    var body: some View {
        HStack(spacing: Layout.sidebarItemGap) {
            // Project icon
            ProjectFavicon()

            // Name + path
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(Fonts.primary(size: 15, weight: .medium))
                    .foregroundStyle(isActive ? theme.text : theme.textMuted)
                    .lineLimit(1)

                Text(project.displayPath)
                    .font(Fonts.primary(size: 13))
                    .foregroundStyle(theme.textDim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Terminal count + pulse dot
            if terminalCount > 0 {
                HStack(spacing: 4) {
                    PulseDot(color: theme.accent, glowColor: theme.accentGlow)
                    if terminalCount > 1 {
                        Text("\(terminalCount)")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.accent)
                    }
                }
            }

            // Remove button — only visible on hover
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isRemoveHovered ? theme.danger : theme.textDim)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.1), value: isHovered)
            .onHover { isRemoveHovered = $0 }
        }
        .padding(Layout.sidebarItemPadding)
        .background(
            isActive
                ? theme.accent.opacity(0.04)
                : (isHovered ? theme.accent2.opacity(0.04) : Color.clear)
        )
        // Left border indicator — flush to edge, outside padding (matches CSS border-left)
        .overlay(alignment: .leading) {
            theme.accent
                .frame(width: Layout.sidebarItemBorderWidth)
                .opacity(isActive ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
    }
}

/// Animated pulsing dot indicating active terminals.
struct PulseDot: View {
    let color: Color
    let glowColor: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: glowColor, radius: 4, x: 0, y: 0)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Blink/Views/SidebarProjectItem.swift
git commit -m "feat: add SidebarProjectItem with active, hover, pulse states"
```

---

### Task 12: Sidebar (full implementation)

Replace the stub with the complete sidebar: header, scrollable project list, settings footer.

**Files:**
- Modify: `Blink/Views/Sidebar.swift`

- [ ] **Step 1: Replace Sidebar.swift with full implementation**

```swift
import SwiftUI

struct Sidebar: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    @State private var isAddHovered = false
    @State private var isSettingsHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Header: "PROJECTS" + add button
            HStack {
                Text("PROJECTS")
                    .font(Fonts.primary(size: 11, weight: .medium))
                    .tracking(0.55) // Tailwind tracking-wider = 0.05em * 11pt
                    .textCase(.uppercase)
                    .foregroundStyle(theme.textDim)

                Spacer()

                Button(action: { /* non-functional in M1 */ }) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(isAddHovered ? theme.text : theme.textMuted)
                }
                .buttonStyle(.plain)
                .onHover { isAddHovered = $0 }
            }
            .padding(Layout.sidebarHeaderPadding)

            // Project list or empty state
            if store.projects.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundStyle(theme.textDim.opacity(0.5))
                    Text("No projects yet")
                        .font(Fonts.primary(size: 16))
                        .foregroundStyle(theme.textMuted)
                    Text("Tap the icon above to add one")
                        .font(Fonts.primary(size: 12))
                        .foregroundStyle(theme.textDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(store.projects) { project in
                            SidebarProjectItem(
                                project: project,
                                isActive: store.activeProjectId == project.id,
                                terminalCount: store.terminalCount(for: project.id),
                                onSelect: { store.setActiveProject(project.id) },
                                onRemove: { store.removeProject(project.id) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
            }

            // Footer: settings button
            VStack(spacing: 0) {
                theme.border.frame(height: 1)
                Button(action: { /* settings — M2+ */ }) {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .light))
                        Text("Settings")
                            .font(Fonts.primary(size: 12.5))
                    }
                    .foregroundStyle(isSettingsHovered ? theme.text : theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Layout.sidebarSettingsHeight)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .onHover { isSettingsHovered = $0 }
            }
        }
        .frame(maxHeight: .infinity)
        .background(theme.bg2)
        .overlay(alignment: .trailing) {
            theme.border.frame(width: 1)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Blink/Views/Sidebar.swift
git commit -m "feat: implement full Sidebar with header, project list, settings footer"
```

---

## Chunk 5: TabBar + Final Integration

### Task 13: TabBar (full implementation)

Replace the stub with the complete tab bar: KRUX logo, tab pills with hover/close, plus button.

**Files:**
- Modify: `Blink/Views/TabBar.swift`

- [ ] **Step 1: Replace TabBar.swift with full implementation**

```swift
import SwiftUI

struct TabBar: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    @State private var isPlusHovered = false

    private var projectTabs: [Tab] {
        guard let id = store.activeProjectId else { return [] }
        return store.projectTabs(for: id)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Logo area — width matches sidebar
            HStack {
                Text("KRUX")
                    .font(Fonts.primary(size: 11, weight: .bold))
                    .tracking(1.65) // 0.15em * 11pt = 1.65pt
                    .textCase(.uppercase)
                    .foregroundStyle(theme.textDim)
            }
            .frame(width: Layout.sidebarWidth, alignment: .leading)
            .padding(.leading, Layout.tabBarLogoPaddingLeft)
            .overlay(alignment: .trailing) {
                theme.border.frame(width: 1)
            }

            // Tab pills — scrollable
            if store.activeProjectId != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(projectTabs) { tab in
                            TabPill(
                                tab: tab,
                                isActive: store.activeTabId == tab.id,
                                onSelect: { store.setActiveTab(tab.id) },
                                onClose: { store.closeTab(tab.id) }
                            )
                        }
                    }
                }

                // Plus button
                Button(action: { /* new tab — future */ }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isPlusHovered ? theme.accent : theme.textDim)
                        .frame(width: Layout.tabBarHeight, height: Layout.tabBarHeight)
                }
                .buttonStyle(.plain)
                .onHover { isPlusHovered = $0 }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg2)
        .overlay(alignment: .bottom) {
            theme.border.frame(height: 1)
        }
    }
}

struct TabPill: View {
    @Environment(\.theme) private var theme

    let tab: Tab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false
    @State private var isCloseHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.label)
                .font(Fonts.primary(size: 12))
                .foregroundStyle(isActive || isHovered ? theme.text : theme.textMuted)
                .lineLimit(1)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isCloseHovered ? theme.danger : theme.textDim)
                    .padding(2)
                    .background(
                        isCloseHovered
                            ? theme.danger.opacity(0.15)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.1), value: isHovered)
            .onHover { isCloseHovered = $0 }
        }
        .padding(.horizontal, Layout.tabPillPaddingH)
        .frame(maxHeight: .infinity)
        .background(
            isActive || isHovered
                ? Color.white.opacity(0.02)
                : Color.clear
        )
        .overlay(alignment: .bottom) {
            if isActive {
                theme.accent.frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Blink/Views/TabBar.swift
git commit -m "feat: implement TabBar with logo, tab pills, hover states, close buttons"
```

---

### Task 14: Visual verification and final polish

Run the app and compare against Krux side-by-side. Fix any visual discrepancies.

**Files:**
- May modify any view file for pixel adjustments

- [ ] **Step 1: Build and launch the app**

```bash
xcodebuild -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
open "$(xcodebuild -project Blink.xcodeproj -scheme Blink -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')/Blink.app"
```

- [ ] **Step 2: Visual comparison checklist**

With both Krux and Blink open side-by-side, verify:

- [ ] Sidebar background color matches (`#0c1018`)
- [ ] Main background matches (`#080810`)
- [ ] Border color matches (`#1e2d40`)
- [ ] "KRUX" logo position, size, color, letter-spacing
- [ ] "PROJECTS" header position, size, weight, letter-spacing
- [ ] Project item padding and spacing
- [ ] Project name font size (15pt) and color
- [ ] Project path font size (13pt), color, and `~` substitution
- [ ] Active project left border (3pt, accent green)
- [ ] Active project background tint (4% accent)
- [ ] Hover state on inactive project (4% accent2)
- [ ] Remove button appears on hover, turns red on hover
- [ ] Pulse dot animates on projects with terminals
- [ ] Terminal count number only appears when >= 2
- [ ] Settings button at bottom, correct icon and text
- [ ] Tab bar height (36pt)
- [ ] Tab pill text, active underline, hover states
- [ ] Tab close button appears on hover
- [ ] Status line: project name centered, terminal count on right
- [ ] Start screen when no project selected
- [ ] Fonts are JetBrains Mono throughout

- [ ] **Step 3: Fix any discrepancies found**

Adjust values in the source files as needed. Common SwiftUI tweaks:
- `.tracking()` values may need adjustment to match CSS `letter-spacing`
- `.padding()` may need fine-tuning vs CSS box model
- Font rendering differences between WebKit and Core Text

- [ ] **Step 4: Run all tests to confirm nothing broke**

```bash
xcodebuild test -project Blink.xcodeproj -scheme Blink -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: All tests PASS.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat: complete Milestone 1 — sidebar visual parity with Krux"
```
