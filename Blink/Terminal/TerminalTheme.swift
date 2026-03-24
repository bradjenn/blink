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
    func toConfigString(
        backgroundOpacity: Double = 0,
        fontFamily: String = "MesloLGS Nerd Font Mono",
        fontSize: Double = 19,
        cursorStyle: CursorStyle = .block
    ) -> String {
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
        lines.append("font-family = \(fontFamily)")
        lines.append("font-size = \(Int(fontSize))")
        lines.append("cursor-shape = \(cursorStyle.rawValue)")
        lines.append("window-padding-x = 16")
        lines.append("window-padding-y = 10")
        lines.append("audible-bell = false")
        lines.append("visual-bell = false")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Build a spotatui config string from this theme's colors.
    func toSpotatuiConfigString() -> String {
        let primaryAccent = cursorColor.lowercased() != foreground.lowercased() ? cursorColor : palette[4]
        let secondaryAccent = palette[6]
        let inactiveBorder = palette[8]
        let errorText = palette.count > 9 ? palette[9] : palette[1]

        return """
        theme:
          active: "\(Self.spotatuiRGB(from: secondaryAccent))"
          banner: "\(Self.spotatuiRGB(from: secondaryAccent))"
          error_border: "\(Self.spotatuiRGB(from: palette[1]))"
          error_text: "\(Self.spotatuiRGB(from: errorText))"
          hint: "\(Self.spotatuiRGB(from: palette[3]))"
          hovered: "\(Self.spotatuiRGB(from: palette[5]))"
          inactive: "\(Self.spotatuiRGB(from: inactiveBorder))"
          playbar_background: "\(Self.spotatuiRGB(from: palette[0]))"
          playbar_progress: "\(Self.spotatuiRGB(from: secondaryAccent))"
          playbar_progress_text: "\(Self.spotatuiRGB(from: primaryAccent))"
          playbar_text: "\(Self.spotatuiRGB(from: foreground))"
          selected: "\(Self.spotatuiRGB(from: primaryAccent))"
          text: "\(Self.spotatuiRGB(from: foreground))"
          header: "\(Self.spotatuiRGB(from: palette[15]))"
        behavior:
          show_loading_indicator: false
          set_window_title: false
        """
    }

    func spotatuiLaunchCommand() -> String {
        guard let configPath = writeSpotatuiConfig() else {
            return "spotatui"
        }

        return "spotatui --config \(Self.shellQuote(configPath))"
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

    private func writeSpotatuiConfig() -> String? {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directoryURL = cachesURL.appendingPathComponent("blink-spotatui", isDirectory: true)
        let configURL = directoryURL.appendingPathComponent("config.yml")

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try toSpotatuiConfigString().write(to: configURL, atomically: true, encoding: .utf8)
            return configURL.path
        } catch {
            print("[TerminalTheme] Failed to write spotatui config: \(error)")
            return nil
        }
    }

    private static func spotatuiRGB(from hex: String) -> String {
        let sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix("#")
        guard sanitized.count == 6 else { return "255, 255, 255" }

        let red = Int(sanitized.prefix(2), radix: 16) ?? 255
        let greenStart = sanitized.index(sanitized.startIndex, offsetBy: 2)
        let greenEnd = sanitized.index(greenStart, offsetBy: 2)
        let blueStart = sanitized.index(greenEnd, offsetBy: 0)
        let blueEnd = sanitized.index(blueStart, offsetBy: 2)
        let green = Int(sanitized[greenStart..<greenEnd], radix: 16) ?? 255
        let blue = Int(sanitized[blueStart..<blueEnd], radix: 16) ?? 255

        return "\(red), \(green), \(blue)"
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

enum YaziLauncher {
    static func command(theme: TerminalTheme?) -> String {
        let configHome = writeConfigHome(theme: theme) ?? defaultConfigHome()
        return "env YAZI_CONFIG_HOME=\(shellQuote(configHome)) EDITOR=nvim VISUAL=nvim yazi"
    }

    private static func writeConfigHome(theme: TerminalTheme?) -> String? {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directoryURL = cachesURL.appendingPathComponent("blink-yazi", isDirectory: true)
        let configURL = directoryURL.appendingPathComponent("yazi.toml")
        let themeURL = directoryURL.appendingPathComponent("theme.toml")

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try configContents.write(to: configURL, atomically: true, encoding: .utf8)
            if let theme {
                try themeContents(theme).write(to: themeURL, atomically: true, encoding: .utf8)
            } else if FileManager.default.fileExists(atPath: themeURL.path) {
                try FileManager.default.removeItem(at: themeURL)
            }
            return directoryURL.path
        } catch {
            print("[YaziLauncher] Failed to write Yazi config: \(error)")
            return nil
        }
    }

    private static func defaultConfigHome() -> String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".config/yazi")
    }

    private static var configContents: String {
        """
        [mgr]
        title_format = ""
        """
    }

    private static func themeContents(_ theme: TerminalTheme) -> String {
        let background = theme.background
        let foreground = theme.foreground
        let accent = theme.cursorColor.lowercased() != foreground.lowercased() ? theme.cursorColor : theme.palette[4]
        let accent2 = theme.palette[6]
        let muted = theme.palette[8]
        let surface = theme.palette[0]
        let danger = theme.palette[1]
        let success = theme.palette[2]
        let warning = theme.palette[3]
        let directory = theme.palette[4]

        return """
        [app]
        overall = { bg = "\(background)" }

        [mgr]
        cwd = { fg = "\(accent)", bold = true }
        find_keyword = { fg = "\(warning)", bold = true }
        find_position = { fg = "\(accent2)", bold = true }
        symlink_target = { fg = "\(accent2)" }
        border_symbol = "│"
        border_style = { fg = "\(muted)" }

        [status]
        overall = { fg = "\(foreground)", bg = "\(surface)" }
        perm_type = { fg = "\(accent2)" }
        perm_read = { fg = "\(success)" }
        perm_write = { fg = "\(warning)" }
        perm_exec = { fg = "\(danger)" }
        perm_sep = { fg = "\(muted)" }
        progress_label = { fg = "\(foreground)", bold = true }
        progress_normal = { fg = "\(accent2)", bg = "\(accent2)" }
        progress_error = { fg = "\(danger)", bg = "\(danger)" }

        [which]
        mask = { bg = "\(background)" }
        cand = { fg = "\(foreground)" }
        rest = { fg = "\(muted)" }
        desc = { fg = "\(accent2)" }
        separator_style = { fg = "\(muted)" }

        [confirm]
        border = { fg = "\(muted)" }
        title = { fg = "\(accent)", bold = true }
        body = { fg = "\(foreground)" }
        list = { fg = "\(foreground)" }
        btn_yes = { fg = "\(background)", bg = "\(success)", bold = true }
        btn_no = { fg = "\(background)", bg = "\(danger)", bold = true }
        btn_labels = ["Yes", "No"]

        [spot]
        border = { fg = "\(muted)" }
        title = { fg = "\(accent)", bold = true }
        tbl_col = { fg = "\(accent2)" }
        tbl_cell = { fg = "\(foreground)" }

        [notify]
        title_info = { fg = "\(accent2)", bold = true }
        title_warn = { fg = "\(warning)", bold = true }
        title_error = { fg = "\(danger)", bold = true }

        [input]
        border = { fg = "\(muted)" }
        title = { fg = "\(accent)", bold = true }
        value = { fg = "\(foreground)" }
        selected = { reversed = true }

        [tasks]
        border = { fg = "\(muted)" }
        title = { fg = "\(accent)", bold = true }

        [help]
        on = { fg = "\(accent)", bold = true }
        run = { fg = "\(accent2)" }
        desc = { fg = "\(foreground)" }
        footer = { fg = "\(muted)" }

        [filetype]
        rules = [
          { url = "*/", fg = "\(directory)" },
          { url = "*", fg = "\(foreground)" },
        ]
        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

enum NvimLauncher {
    static func command() -> String {
        "env EDITOR=nvim VISUAL=nvim nvim"
    }
}
