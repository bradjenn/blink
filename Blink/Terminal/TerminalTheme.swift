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
    private struct SemanticPalette {
        let keyword: String
        let function: String
        let type: String
        let string: String
        let constant: String
        let special: String
        let operatorColor: String
        let comment: String
        let statusline: String
        let pmenuSelection: String
        let search: String
        let incSearch: String
        let visual: String
        let cursorLine: String
        let keywordItalic: Bool
        let commentItalic: Bool
        let functionBold: Bool
    }

    static func command(theme: TerminalTheme?, backgroundOpacity: Double = 1.0) -> String {
        guard let theme, let themePath = writeThemeFile(theme: theme, backgroundOpacity: backgroundOpacity) else {
            return "env EDITOR=nvim VISUAL=nvim nvim"
        }

        return "env EDITOR=nvim VISUAL=nvim nvim \"+lua dofile([[\(themePath)]])\""
    }

    private static func writeThemeFile(theme: TerminalTheme, backgroundOpacity: Double) -> String? {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directoryURL = cachesURL.appendingPathComponent("blink-nvim", isDirectory: true)
        let themeURL = directoryURL.appendingPathComponent("blink-theme.lua")

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try themeContents(theme, backgroundOpacity: backgroundOpacity).write(to: themeURL, atomically: true, encoding: .utf8)
            return themeURL.path
        } catch {
            print("[NvimLauncher] Failed to write Neovim theme: \(error)")
            return nil
        }
    }

    private static func themeContents(_ theme: TerminalTheme, backgroundOpacity: Double) -> String {
        let background = luaColor(theme.background)
        let foreground = luaColor(theme.foreground)
        let accent = luaColor(theme.cursorColor.lowercased() != theme.foreground.lowercased() ? theme.cursorColor : theme.palette[4])
        let accent2 = luaColor(theme.palette[6])
        let surface = luaColor(theme.palette[0])
        let surface2 = luaColor(theme.palette[8])
        let red = luaColor(theme.palette[1])
        let green = luaColor(theme.palette[2])
        let yellow = luaColor(theme.palette[3])
        let blue = luaColor(theme.palette[4])
        let magenta = luaColor(theme.palette[5])
        let cyan = luaColor(theme.palette[6])
        let comment = luaColor(theme.palette[8])
        let white = luaColor(theme.palette[15])
        let isTransparent = backgroundOpacity < 0.999
        let semantics = semanticPalette(for: theme)
        let favoriteScript = favoriteColorschemeScript(for: theme, isTransparent: isTransparent) ?? ""
        let bundledThemePaths = bundledRuntimePaths().map(luaString).joined(separator: ",\n  ")
        let lualineThemeName = favoriteLualineThemeName(for: theme).map(luaString) ?? "nil"

        return """
        vim.o.termguicolors = true
        vim.g.blink_session = true
        vim.g.colors_name = "blink-\(luaIdentifier(theme.name))"

        local bundled_runtimepaths = {
          \(bundledThemePaths)
        }
        local favorite_lualine_theme = \(lualineThemeName)
        vim.g.blink_lualine_theme = favorite_lualine_theme

        for _, path in ipairs(bundled_runtimepaths) do
          if path ~= "" then
            vim.opt.runtimepath:prepend(path)
          end
        end

        local c = {
          bg = "\(background)",
          fg = "\(foreground)",
          accent = "\(accent)",
          accent2 = "\(accent2)",
          surface = "\(surface)",
          surface2 = "\(surface2)",
          red = "\(red)",
          green = "\(green)",
          yellow = "\(yellow)",
          blue = "\(blue)",
          magenta = "\(magenta)",
          cyan = "\(cyan)",
          comment = "\(comment)",
          white = "\(white)",
          normal_bg = "\(isTransparent ? "NONE" : background)",
          keyword = "\(semantics.keyword)",
          fn = "\(semantics.function)",
          type = "\(semantics.type)",
          string = "\(semantics.string)",
          constant = "\(semantics.constant)",
          special = "\(semantics.special)",
          operator = "\(semantics.operatorColor)",
          semantic_comment = "\(semantics.comment)",
          status = "\(semantics.statusline)",
          pmenu_sel = "\(semantics.pmenuSelection)",
          search = "\(semantics.search)",
          incsearch = "\(semantics.incSearch)",
          visual = "\(semantics.visual)",
          cursorline = "\(semantics.cursorLine)",
        }

        local set = vim.api.nvim_set_hl

        local function set_terminal_colors()
          for i, color in ipairs({
            c.bg, c.red, c.green, c.yellow, c.blue, c.magenta, c.cyan, c.fg,
            c.comment, c.red, c.green, c.yellow, c.blue, c.magenta, c.cyan, c.white,
          }) do
            vim.g["terminal_color_" .. (i - 1)] = color
          end
        end

        local function apply_transparent_background()
          for _, name in ipairs({
            "Normal", "NormalNC", "SignColumn", "FoldColumn", "LineNr", "EndOfBuffer", "WinSeparator", "VertSplit"
          }) do
            set(0, name, { bg = "NONE" })
          end
        end

        local function sync_lualine_theme()
          local attempts = 0

          local function apply()
            attempts = attempts + 1
            local ok, lualine = pcall(require, "lualine")
            if not ok then
              if attempts < 20 then
                vim.defer_fn(apply, 100)
              end
              return
            end

            local config = lualine.get_config()
            if type(config) ~= "table" or type(config.options) ~= "table" then
              return
            end

            config.options.theme = favorite_lualine_theme or "auto"
            lualine.setup(config)
            lualine.refresh()
          end

          vim.schedule(apply)
        end

        local function try_colorscheme(names)
          for _, name in ipairs(names) do
            if pcall(vim.cmd.colorscheme, name) then
              return true
            end
          end
          return false
        end

        local function apply_fallback_theme()
          local groups = {
            Normal = { fg = c.fg, bg = c.normal_bg },
            NormalNC = { fg = c.fg, bg = c.normal_bg },
            EndOfBuffer = { fg = c.semantic_comment, bg = c.normal_bg },
            NormalFloat = { fg = c.fg, bg = c.surface },
            FloatBorder = { fg = c.surface2, bg = c.surface },
            FloatTitle = { fg = c.accent, bg = c.surface, bold = true },
            SignColumn = { fg = c.surface2, bg = c.normal_bg },
            FoldColumn = { fg = c.semantic_comment, bg = c.normal_bg },
            LineNr = { fg = c.semantic_comment, bg = c.normal_bg },
            CursorLineNr = { fg = c.accent, bg = c.normal_bg, bold = true },
            CursorLine = { bg = c.cursorline },
            CursorColumn = { bg = c.cursorline },
            ColorColumn = { bg = c.cursorline },
            WinSeparator = { fg = c.surface2, bg = c.normal_bg },
            VertSplit = { fg = c.surface2, bg = c.normal_bg },
            Visual = { bg = c.visual },
            Search = { fg = c.bg, bg = c.search, bold = true },
            IncSearch = { fg = c.bg, bg = c.incsearch, bold = true },
            CurSearch = { fg = c.bg, bg = c.incsearch, bold = true },
            MatchParen = { fg = c.bg, bg = c.cyan, bold = true },
            Pmenu = { fg = c.fg, bg = c.surface },
            PmenuSel = { fg = c.bg, bg = c.pmenu_sel, bold = true },
            PmenuSbar = { bg = c.surface2 },
            PmenuThumb = { bg = c.accent2 },
            StatusLine = { fg = c.bg, bg = c.status, bold = true },
            StatusLineNC = { fg = c.fg, bg = c.surface },
            TabLine = { fg = c.fg, bg = c.surface },
            TabLineSel = { fg = c.bg, bg = c.status, bold = true },
            TabLineFill = { bg = c.bg },
            Directory = { fg = c.blue, bold = true },
            Comment = { fg = c.semantic_comment, italic = \(luaBool(semantics.commentItalic)) },
            Constant = { fg = c.constant },
            String = { fg = c.string },
            Character = { fg = c.string },
            Number = { fg = c.constant },
            Boolean = { fg = c.constant, bold = true },
            Identifier = { fg = c.fg },
            Function = { fg = c.fn, bold = \(luaBool(semantics.functionBold)) },
            Statement = { fg = c.keyword },
            Keyword = { fg = c.keyword, italic = \(luaBool(semantics.keywordItalic)) },
            Operator = { fg = c.operator },
            Type = { fg = c.type },
            Special = { fg = c.special },
            PreProc = { fg = c.accent },
            Title = { fg = c.accent, bold = true },
            Error = { fg = c.red, bold = true },
            WarningMsg = { fg = c.yellow, bold = true },
            DiagnosticError = { fg = c.red },
            DiagnosticWarn = { fg = c.yellow },
            DiagnosticInfo = { fg = c.blue },
            DiagnosticHint = { fg = c.cyan },
            DiagnosticOk = { fg = c.green },
            DiagnosticVirtualTextError = { fg = c.red, bg = c.surface },
            DiagnosticVirtualTextWarn = { fg = c.yellow, bg = c.surface },
            DiagnosticVirtualTextInfo = { fg = c.blue, bg = c.surface },
            DiagnosticVirtualTextHint = { fg = c.cyan, bg = c.surface },
            DiagnosticUnderlineError = { undercurl = true, sp = c.red },
            DiagnosticUnderlineWarn = { undercurl = true, sp = c.yellow },
            DiagnosticUnderlineInfo = { undercurl = true, sp = c.blue },
            DiagnosticUnderlineHint = { undercurl = true, sp = c.cyan },
            DiffAdd = { bg = c.surface, fg = c.green },
            DiffChange = { bg = c.surface, fg = c.blue },
            DiffDelete = { bg = c.surface, fg = c.red },
            DiffText = { bg = c.cursorline, fg = c.accent },
            GitSignsAdd = { fg = c.green, bg = c.normal_bg },
            GitSignsChange = { fg = c.blue, bg = c.normal_bg },
            GitSignsDelete = { fg = c.red, bg = c.normal_bg },
            TelescopeNormal = { fg = c.fg, bg = c.surface },
            TelescopeBorder = { fg = c.surface2, bg = c.surface },
            TelescopePromptNormal = { fg = c.fg, bg = c.surface },
            TelescopePromptBorder = { fg = c.surface2, bg = c.surface },
            TelescopePromptTitle = { fg = c.bg, bg = c.status, bold = true },
            TelescopeResultsTitle = { fg = c.bg, bg = c.surface2, bold = true },
            TelescopePreviewTitle = { fg = c.bg, bg = c.accent2, bold = true },
            TelescopeSelection = { bg = c.cursorline, bold = true },
            BlinkCmpMenu = { fg = c.fg, bg = c.surface },
            BlinkCmpMenuBorder = { fg = c.surface2, bg = c.surface },
            BlinkCmpLabelMatch = { fg = c.accent, bold = true },
            ["@comment"] = { link = "Comment" },
            ["@keyword"] = { link = "Keyword" },
            ["@keyword.function"] = { link = "Keyword" },
            ["@keyword.return"] = { link = "Keyword" },
            ["@conditional"] = { link = "Keyword" },
            ["@repeat"] = { link = "Keyword" },
            ["@string"] = { link = "String" },
            ["@string.escape"] = { fg = c.special },
            ["@character"] = { link = "Character" },
            ["@number"] = { link = "Number" },
            ["@boolean"] = { link = "Boolean" },
            ["@constant"] = { link = "Constant" },
            ["@constant.builtin"] = { fg = c.constant, bold = true },
            ["@constructor"] = { fg = c.type, bold = true },
            ["@function"] = { link = "Function" },
            ["@function.builtin"] = { fg = c.fn, bold = true },
            ["@function.method"] = { fg = c.fn },
            ["@module"] = { fg = c.type },
            ["@type"] = { link = "Type" },
            ["@type.builtin"] = { fg = c.type, italic = true },
            ["@property"] = { fg = c.fg },
            ["@field"] = { fg = c.fg },
            ["@variable"] = { fg = c.fg },
            ["@variable.builtin"] = { fg = c.special, italic = true },
            ["@operator"] = { link = "Operator" },
            ["@punctuation.delimiter"] = { fg = c.surface2 },
            ["@punctuation.bracket"] = { fg = c.surface2 },
            ["@tag"] = { fg = c.keyword },
            ["@tag.attribute"] = { fg = c.special },
          }

          for name, spec in pairs(groups) do
            set(0, name, spec)
          end
        end

        local applied = false
        \(favoriteScript)

        if applied then
          if c.normal_bg == "NONE" then
            apply_transparent_background()
          end
          sync_lualine_theme()
        else
          apply_fallback_theme()
        end

        set_terminal_colors()
        """
    }

    private static func semanticPalette(for theme: TerminalTheme) -> SemanticPalette {
        switch theme.name {
        case "Josean":
            return SemanticPalette(
                keyword: luaColor(theme.palette[6]),
                function: luaColor(theme.cursorColor),
                type: luaColor(theme.palette[3]),
                string: luaColor(theme.palette[2]),
                constant: luaColor(theme.palette[3]),
                special: luaColor(theme.palette[5]),
                operatorColor: luaColor(theme.palette[4]),
                comment: luaColor(theme.palette[8]),
                statusline: luaColor(theme.cursorColor),
                pmenuSelection: luaColor(theme.palette[4]),
                search: luaColor(theme.palette[3]),
                incSearch: luaColor(theme.cursorColor),
                visual: luaColor(theme.selectionBackground),
                cursorLine: luaColor(theme.palette[0]),
                keywordItalic: false,
                commentItalic: false,
                functionBold: true
            )
        case "Dracula":
            return SemanticPalette(
                keyword: luaColor(theme.palette[5]),
                function: luaColor(theme.palette[2]),
                type: luaColor(theme.palette[6]),
                string: luaColor(theme.palette[3]),
                constant: luaColor(theme.palette[5]),
                special: luaColor(theme.palette[6]),
                operatorColor: luaColor(theme.palette[5]),
                comment: luaColor(theme.palette[8]),
                statusline: luaColor(theme.palette[5]),
                pmenuSelection: luaColor(theme.palette[5]),
                search: luaColor(theme.palette[3]),
                incSearch: luaColor(theme.palette[6]),
                visual: luaColor(theme.selectionBackground),
                cursorLine: luaColor(theme.palette[0]),
                keywordItalic: false,
                commentItalic: true,
                functionBold: true
            )
        case "TokyoNight":
            return SemanticPalette(
                keyword: luaColor(theme.palette[5]),
                function: luaColor(theme.palette[4]),
                type: luaColor(theme.palette[6]),
                string: luaColor(theme.palette[2]),
                constant: luaColor(theme.palette[3]),
                special: luaColor(theme.palette[6]),
                operatorColor: luaColor(theme.palette[5]),
                comment: luaColor(theme.palette[8]),
                statusline: luaColor(theme.palette[4]),
                pmenuSelection: luaColor(theme.palette[4]),
                search: luaColor(theme.palette[3]),
                incSearch: luaColor(theme.palette[5]),
                visual: luaColor(theme.selectionBackground),
                cursorLine: luaColor(theme.palette[0]),
                keywordItalic: true,
                commentItalic: true,
                functionBold: true
            )
        case "Catppuccin Mocha":
            return SemanticPalette(
                keyword: luaColor(theme.palette[5]),
                function: luaColor(theme.palette[4]),
                type: luaColor(theme.palette[3]),
                string: luaColor(theme.palette[2]),
                constant: luaColor(theme.palette[5]),
                special: luaColor(theme.palette[6]),
                operatorColor: luaColor(theme.palette[5]),
                comment: luaColor(theme.palette[8]),
                statusline: luaColor(theme.cursorColor),
                pmenuSelection: luaColor(theme.palette[4]),
                search: luaColor(theme.palette[3]),
                incSearch: luaColor(theme.cursorColor),
                visual: luaColor(theme.selectionBackground),
                cursorLine: luaColor(theme.palette[0]),
                keywordItalic: false,
                commentItalic: true,
                functionBold: true
            )
        case "Gruvbox Dark":
            return SemanticPalette(
                keyword: luaColor(theme.palette[1]),
                function: luaColor(theme.palette[2]),
                type: luaColor(theme.palette[3]),
                string: luaColor(theme.palette[2]),
                constant: luaColor(theme.palette[5]),
                special: luaColor(theme.palette[6]),
                operatorColor: luaColor(theme.palette[1]),
                comment: luaColor(theme.palette[8]),
                statusline: luaColor(theme.palette[3]),
                pmenuSelection: luaColor(theme.palette[6]),
                search: luaColor(theme.palette[3]),
                incSearch: luaColor(theme.palette[1]),
                visual: luaColor(theme.selectionBackground),
                cursorLine: luaColor(theme.palette[0]),
                keywordItalic: false,
                commentItalic: false,
                functionBold: false
            )
        case "Nord":
            return SemanticPalette(
                keyword: luaColor(theme.palette[5]),
                function: luaColor(theme.palette[4]),
                type: luaColor(theme.palette[6]),
                string: luaColor(theme.palette[2]),
                constant: luaColor(theme.palette[3]),
                special: luaColor(theme.palette[6]),
                operatorColor: luaColor(theme.palette[5]),
                comment: luaColor(theme.palette[8]),
                statusline: luaColor(theme.palette[6]),
                pmenuSelection: luaColor(theme.palette[4]),
                search: luaColor(theme.palette[3]),
                incSearch: luaColor(theme.palette[6]),
                visual: luaColor(theme.selectionBackground),
                cursorLine: luaColor(theme.palette[0]),
                keywordItalic: false,
                commentItalic: false,
                functionBold: true
            )
        case "Atom One Dark":
            return SemanticPalette(
                keyword: luaColor(theme.palette[5]),
                function: luaColor(theme.palette[4]),
                type: luaColor(theme.palette[3]),
                string: luaColor(theme.palette[2]),
                constant: luaColor(theme.palette[1]),
                special: luaColor(theme.palette[6]),
                operatorColor: luaColor(theme.palette[5]),
                comment: luaColor(theme.palette[8]),
                statusline: luaColor(theme.palette[4]),
                pmenuSelection: luaColor(theme.palette[4]),
                search: luaColor(theme.palette[3]),
                incSearch: luaColor(theme.palette[5]),
                visual: luaColor(theme.selectionBackground),
                cursorLine: luaColor(theme.palette[0]),
                keywordItalic: false,
                commentItalic: true,
                functionBold: false
            )
        case "Solarized Dark Patched":
            return SemanticPalette(
                keyword: luaColor(theme.palette[5]),
                function: luaColor(theme.palette[4]),
                type: luaColor(theme.palette[6]),
                string: luaColor(theme.palette[2]),
                constant: luaColor(theme.palette[3]),
                special: luaColor(theme.palette[1]),
                operatorColor: luaColor(theme.palette[5]),
                comment: luaColor(theme.palette[8]),
                statusline: luaColor(theme.palette[3]),
                pmenuSelection: luaColor(theme.palette[4]),
                search: luaColor(theme.palette[3]),
                incSearch: luaColor(theme.palette[4]),
                visual: luaColor(theme.selectionBackground),
                cursorLine: luaColor(theme.palette[0]),
                keywordItalic: false,
                commentItalic: true,
                functionBold: false
            )
        case "Rose Pine":
            return SemanticPalette(
                keyword: luaColor(theme.palette[5]),
                function: luaColor(theme.palette[4]),
                type: luaColor(theme.palette[6]),
                string: luaColor(theme.palette[3]),
                constant: luaColor(theme.palette[6]),
                special: luaColor(theme.palette[1]),
                operatorColor: luaColor(theme.palette[5]),
                comment: luaColor(theme.palette[8]),
                statusline: luaColor(theme.palette[6]),
                pmenuSelection: luaColor(theme.palette[4]),
                search: luaColor(theme.palette[3]),
                incSearch: luaColor(theme.palette[6]),
                visual: luaColor(theme.selectionBackground),
                cursorLine: luaColor(theme.palette[0]),
                keywordItalic: true,
                commentItalic: true,
                functionBold: false
            )
        case "Kanagawa Wave":
            return SemanticPalette(
                keyword: luaColor(theme.palette[5]),
                function: luaColor(theme.palette[4]),
                type: luaColor(theme.palette[6]),
                string: luaColor(theme.palette[2]),
                constant: luaColor(theme.palette[3]),
                special: luaColor(theme.palette[1]),
                operatorColor: luaColor(theme.palette[5]),
                comment: luaColor(theme.palette[8]),
                statusline: luaColor(theme.palette[3]),
                pmenuSelection: luaColor(theme.palette[4]),
                search: luaColor(theme.palette[3]),
                incSearch: luaColor(theme.palette[4]),
                visual: luaColor(theme.selectionBackground),
                cursorLine: luaColor(theme.palette[0]),
                keywordItalic: false,
                commentItalic: false,
                functionBold: false
            )
        default:
            return SemanticPalette(
                keyword: luaColor(theme.palette[5]),
                function: luaColor(theme.palette[4]),
                type: luaColor(theme.palette[6]),
                string: luaColor(theme.palette[2]),
                constant: luaColor(theme.palette[3]),
                special: luaColor(theme.palette[6]),
                operatorColor: luaColor(theme.palette[6]),
                comment: luaColor(theme.palette[8]),
                statusline: luaColor(theme.cursorColor.lowercased() != theme.foreground.lowercased() ? theme.cursorColor : theme.palette[4]),
                pmenuSelection: luaColor(theme.cursorColor.lowercased() != theme.foreground.lowercased() ? theme.cursorColor : theme.palette[4]),
                search: luaColor(theme.palette[3]),
                incSearch: luaColor(theme.cursorColor.lowercased() != theme.foreground.lowercased() ? theme.cursorColor : theme.palette[4]),
                visual: luaColor(theme.selectionBackground),
                cursorLine: luaColor(theme.palette[0]),
                keywordItalic: true,
                commentItalic: true,
                functionBold: true
            )
        }
    }

    private static func favoriteColorschemeScript(for theme: TerminalTheme, isTransparent: Bool) -> String? {
        switch theme.name {
        case "Josean":
            return """
            do
              local ok, tokyonight = pcall(require, "tokyonight")
              if ok then
                tokyonight.setup({
                  style = "night",
                  transparent = \(luaBool(isTransparent)),
                  styles = {
                    sidebars = "\(isTransparent ? "transparent" : "dark")",
                    floats = "\(isTransparent ? "transparent" : "dark")",
                  },
                  on_colors = function(colors)
                    colors.bg = "#011628"
                    colors.bg_dark = \(isTransparent ? "colors.none" : "\"#011423\"")
                    colors.bg_float = \(isTransparent ? "colors.none" : "\"#011423\"")
                    colors.bg_highlight = "#143652"
                    colors.bg_popup = "#011423"
                    colors.bg_search = "#0A64AC"
                    colors.bg_sidebar = \(isTransparent ? "colors.none" : "\"#011423\"")
                    colors.bg_statusline = \(isTransparent ? "colors.none" : "\"#011423\"")
                    colors.bg_visual = "#275378"
                    colors.border = "#547998"
                    colors.fg = "#CBE0F0"
                    colors.fg_dark = "#B4D0E9"
                    colors.fg_float = "#CBE0F0"
                    colors.fg_gutter = "#627E97"
                    colors.fg_sidebar = "#B4D0E9"
                  end,
                })
                applied = pcall(tokyonight.load)
              end
            end
            """
        case "TokyoNight":
            return """
            do
              local ok, tokyonight = pcall(require, "tokyonight")
              if ok then
                tokyonight.setup({
                  style = "night",
                  transparent = \(luaBool(isTransparent)),
                  styles = {
                    sidebars = "\(isTransparent ? "transparent" : "dark")",
                    floats = "\(isTransparent ? "transparent" : "dark")",
                  },
                })
                applied = pcall(tokyonight.load, { style = "night" })
              end
            end
            """
        case "Catppuccin Mocha":
            return """
            do
              local ok, catppuccin = pcall(require, "catppuccin")
              if ok then
                catppuccin.setup({
                  flavour = "mocha",
                  transparent_background = \(luaBool(isTransparent)),
                })
                applied = try_colorscheme({ "catppuccin-mocha", "catppuccin" })
              end
            end
            """
        case "Dracula":
            return """
            applied = try_colorscheme({ "dracula" })
            """
        case "Gruvbox Dark":
            return """
            do
              local ok, gruvbox = pcall(require, "gruvbox")
              if ok then
                gruvbox.setup({ transparent_mode = \(luaBool(isTransparent)) })
              end
              applied = try_colorscheme({ "gruvbox" })
            end
            """
        case "Nord":
            return """
            applied = try_colorscheme({ "nord" })
            """
        case "Atom One Dark":
            return """
            applied = try_colorscheme({ "onedark", "atomonedark" })
            """
        case "Solarized Dark Patched":
            return """
            applied = try_colorscheme({ "solarized", "solarized8" })
            """
        case "Rose Pine":
            return """
            do
              local ok, rose_pine = pcall(require, "rose-pine")
              if ok then
                rose_pine.setup({ disable_background = \(luaBool(isTransparent)) })
              end
              applied = try_colorscheme({ "rose-pine", "rosepine" })
            end
            """
        case "Kanagawa Wave":
            return """
            do
              local ok, kanagawa = pcall(require, "kanagawa")
              if ok then
                kanagawa.setup({ transparent = \(luaBool(isTransparent)) })
              end
              applied = try_colorscheme({ "kanagawa-wave", "kanagawa" })
            end
            """
        default:
            return nil
        }
    }

    private static func favoriteLualineThemeName(for theme: TerminalTheme) -> String? {
        switch theme.name {
        case "Josean":
            return "tokyonight-night"
        case "TokyoNight":
            return "tokyonight-night"
        case "Catppuccin Mocha":
            return "catppuccin-mocha"
        case "Dracula":
            return "dracula-nvim"
        case "Gruvbox Dark":
            return "gruvbox"
        case "Nord":
            return "nord"
        case "Atom One Dark":
            return "onedark"
        case "Solarized Dark Patched":
            return "solarized"
        case "Rose Pine":
            return "rose-pine"
        case "Kanagawa Wave":
            return "kanagawa-wave"
        default:
            return nil
        }
    }

    private static func bundledRuntimePaths() -> [String] {
        guard let rootURL = Bundle.main.url(forResource: "NvimThemes", withExtension: nil),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return url.path
        }
        .sorted()
    }

    private static func luaBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static func luaIdentifier(_ string: String) -> String {
        string.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private static func luaString(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func luaColor(_ hex: String) -> String {
        hex.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
