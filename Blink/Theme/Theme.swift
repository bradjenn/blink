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
