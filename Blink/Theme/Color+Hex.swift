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

    /// Convert a Color back to a hex string. Returns nil if conversion fails.
    var hexString: String? {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
