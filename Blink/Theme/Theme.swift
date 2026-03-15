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
