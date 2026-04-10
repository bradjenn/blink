import SwiftUI

private let fallbackTheme = Theme(
    id: "fallback", name: "Fallback",
    bg: Color(hex: "#1a1b26"), bg2: Color(hex: "#16161e"),
    border: Color(hex: "#292e42"), accent: Color(hex: "#7aa2f7"),
    accent2: Color(hex: "#2ac3de"), text: Color(hex: "#c0caf5"),
    textMuted: Color(hex: "#c0caf5").opacity(0.6),
    textDim: Color(hex: "#c0caf5").opacity(0.4),
    danger: Color(hex: "#f7768e"), green: Color(hex: "#9ece6a"),
    yellow: Color(hex: "#e0af68"), magenta: Color(hex: "#bb9af7")
)

@MainActor @Observable
final class ThemeManager {
    /// The currently active UI theme (derived from the terminal theme).
    var activeTheme: Theme

    /// The parsed terminal theme for the active selection.
    var activeTerminalTheme: TerminalTheme?

    /// All available theme names (filenames, not parsed).
    var availableThemes: [String] = []

    /// Cache of parsed themes (for color preview dots in picker).
    var parsedCache: [String: TerminalTheme] = [:]

    /// Curated Blink theme set. Keep this intentionally small and balanced.
    static let curatedThemes: [String] = [
        "Josean",
        "Dracula",
        "TokyoNight",
        "Catppuccin Mocha",
        "Rose Pine",
        "Kanagawa Wave",
        "Catppuccin Latte",
        "TokyoNight Day",
        "Kanagawa Lotus",
        "Gruvbox Dark",
        "Everforest Dark Hard",
        "GitHub Dark Default",
        "GitHub Light Default",
        "Rose Pine Dawn",
    ]

    /// Pinned themes shown first in the picker.
    static let favorites: [String] = [
        "Josean",
        "Dracula",
        "TokyoNight",
        "Catppuccin Mocha",
        "Rose Pine",
        "Kanagawa Wave",
        "Gruvbox Dark",
    ]

    init() {
        // Load persisted theme, fall back to Josean
        let defaultName = UserDefaults.standard.string(forKey: "blink.theme") ?? "Josean"
        let allAvailableThemes = Set(TerminalTheme.availableThemes())
        var curatedThemeNames = Self.curatedThemes.filter { allAvailableThemes.contains($0) }
        if allAvailableThemes.contains(defaultName),
           !curatedThemeNames.contains(defaultName) {
            curatedThemeNames.insert(defaultName, at: 0)
        }
        availableThemes = curatedThemeNames

        if let theme = TerminalTheme.load(name: defaultName) {
            activeTerminalTheme = theme
            activeTheme = theme.deriveUITheme()
            parsedCache[defaultName] = theme
        } else {
            activeTheme = fallbackTheme
        }
    }

    /// Switch to a theme by name. Parses the file and derives UI colors.
    func setTheme(name: String) {
        if activeTerminalTheme?.name == name {
            return
        }

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

extension EnvironmentValues {
    @Entry var theme: Theme = fallbackTheme
}
