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

    /// Fallback theme used when no theme file can be loaded.
    static let fallbackTheme = Theme(
        id: "fallback", name: "Fallback",
        bg: Color(hex: "#1a1b26"), bg2: Color(hex: "#16161e"),
        border: Color(hex: "#292e42"), accent: Color(hex: "#7aa2f7"),
        accent2: Color(hex: "#2ac3de"), text: Color(hex: "#c0caf5"),
        textMuted: Color(hex: "#c0caf5").opacity(0.6),
        textDim: Color(hex: "#c0caf5").opacity(0.4),
        danger: Color(hex: "#f7768e"), green: Color(hex: "#9ece6a"),
        yellow: Color(hex: "#e0af68"), magenta: Color(hex: "#bb9af7")
    )

    init() {
        availableThemes = TerminalTheme.availableThemes()

        let defaultName = "Josean"
        if let theme = TerminalTheme.load(name: defaultName) {
            activeTerminalTheme = theme
            activeTheme = theme.deriveUITheme()
            parsedCache[defaultName] = theme
        } else {
            activeTheme = Self.fallbackTheme
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
    static let defaultValue: Theme = ThemeManager.fallbackTheme
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}
