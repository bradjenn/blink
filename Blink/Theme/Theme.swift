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
