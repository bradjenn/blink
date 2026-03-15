import SwiftUI

/// Parsed representation of a Ghostty theme file.
struct TerminalTheme {
    let name: String
    let background: String
    let foreground: String
    let cursorColor: String
    let cursorText: String
    let selectionBackground: String
    let selectionForeground: String
    let palette: [String] // 16 ANSI colors (indices 0-15)

    /// Parse a Ghostty theme file from its contents.
    static func parse(name: String, contents: String) -> TerminalTheme? {
        var bg = "#000000"
        var fg = "#ffffff"
        var cursor = "#ffffff"
        var cursorTxt = "#000000"
        var selBg = "#444444"
        var selFg = "#ffffff"
        var pal = [String](repeating: "#000000", count: 16)

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)

            switch key {
            case "background":
                bg = value
            case "foreground":
                fg = value
            case "cursor-color":
                cursor = value
            case "cursor-text":
                cursorTxt = value
            case "selection-background":
                selBg = value
            case "selection-foreground":
                selFg = value
            default:
                if key == "palette" {
                    let parts = value.split(separator: "=", maxSplits: 1)
                    if parts.count == 2,
                       let idx = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                       idx >= 0, idx < 16 {
                        pal[idx] = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }

        return TerminalTheme(
            name: name,
            background: bg,
            foreground: fg,
            cursorColor: cursor,
            cursorText: cursorTxt,
            selectionBackground: selBg,
            selectionForeground: selFg,
            palette: pal
        )
    }

    /// Load a theme by name from the app bundle's Themes directory.
    static func load(name: String) -> TerminalTheme? {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Themes"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return parse(name: name, contents: contents)
    }

    /// List all available theme names from the bundle.
    static func availableThemes() -> [String] {
        guard let url = Bundle.main.url(forResource: "Themes", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return []
        }
        return files.sorted()
    }

    /// Build a Ghostty config string from this theme's colors.
    func toConfigString(backgroundOpacity: Double = 0) -> String {
        var lines = [String]()
        for (i, color) in palette.enumerated() {
            lines.append("palette = \(i)=\(color)")
        }
        lines.append("background = \(background)")
        lines.append("foreground = \(foreground)")
        lines.append("cursor-color = \(cursorColor)")
        lines.append("cursor-text = \(cursorText)")
        lines.append("selection-background = \(selectionBackground)")
        lines.append("selection-foreground = \(selectionForeground)")
        // Always fully transparent — SwiftUI handles the background layer
        lines.append("background-opacity = 0")
        lines.append("window-padding-x = 16")
        lines.append("window-padding-y = 10")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Hand-tuned accent overrides for favorite themes where auto-derivation
    /// picks the wrong identity color.
    /// Format: theme name → (accent hex, accent2 hex)
    private static let accentOverrides: [String: (String, String)] = [
        "Josean": ("#47ff9c", "#0fc5ed"),
        "Kanagawa Wave": ("#dca561", "#7e9cd8"),
        "Solarized Dark Patched": ("#b58900", "#268bd2"),
        "Rose Pine": ("#ebbcba", "#31748f"),
        "Gruvbox Dark": ("#fabd2f", "#83a598"),
        "Nord": ("#88c0d0", "#81a1c1"),
        "Catppuccin Mocha": ("#cba6f7", "#89dceb"),
    ]

    /// Derive a UI Theme from this terminal theme's palette.
    func deriveUITheme() -> Theme {
        let bgColor = Color(hex: background)
        let fgColor = Color(hex: foreground)
        let pal15Color = Color(hex: palette[15])

        let textColor = fgColor

        // Check for hand-tuned accent overrides first, then auto-derive
        let accentHex: String
        let accent2Hex: String
        if let override_ = Self.accentOverrides[name] {
            accentHex = override_.0
            accent2Hex = override_.1
        } else {
            accentHex = (cursorColor.lowercased() != foreground.lowercased()) ? cursorColor : palette[4]
            accent2Hex = palette[6]
        }

        return Theme(
            id: name,
            name: name,
            bg: bgColor,
            bg2: Self.adjustBrightness(bgColor, by: -0.08),
            border: Self.adjustBrightness(bgColor, by: 0.12),
            accent: Color(hex: accentHex),
            accent2: Color(hex: accent2Hex),
            text: textColor,
            textMuted: textColor.opacity(0.6),
            textDim: textColor.opacity(0.4),
            danger: Color(hex: palette[1]),
            green: Color(hex: palette[2]),
            yellow: Color(hex: palette[3]),
            magenta: Color(hex: palette[5])
        )
    }

    // MARK: - Color Utilities

    private static func adjustBrightness(_ color: Color, by amount: Double) -> Color {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let newB = max(0, min(1, b + CGFloat(amount)))
        return Color(NSColor(hue: h, saturation: s, brightness: newB, alpha: a))
    }

    private static func brighterColor(_ a: Color, _ b: Color) -> Color {
        let nsA = NSColor(a).usingColorSpace(.sRGB) ?? NSColor(a)
        let nsB = NSColor(b).usingColorSpace(.sRGB) ?? NSColor(b)
        var bA: CGFloat = 0, bB: CGFloat = 0
        nsA.getHue(nil, saturation: nil, brightness: &bA, alpha: nil)
        nsB.getHue(nil, saturation: nil, brightness: &bB, alpha: nil)
        return bA >= bB ? a : b
    }
}
