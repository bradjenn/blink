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
        cursorStyle: CursorStyle = .block,
        cursorBlink: Bool = true
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
        lines.append("cursor-style = \(cursorStyle.rawValue)")
        lines.append("cursor-style-blink = \(cursorBlink)")
        lines.append("shell-integration-features = no-cursor")
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
        let editorCommand = NvimLauncher.editorCommand(theme: theme)
        return "env YAZI_CONFIG_HOME=\(shellQuote(configHome)) EDITOR=\(shellQuote(editorCommand)) VISUAL=\(shellQuote(editorCommand)) yazi"
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

enum FileEditorLauncher: String, CaseIterable {
    case blinkNeovim
    case cursor
    case zed
    case vsCode
    case custom

    var displayName: String {
        switch self {
        case .blinkNeovim:
            "Blink Neovim"
        case .cursor:
            "Cursor"
        case .zed:
            "Zed"
        case .vsCode:
            "VS Code"
        case .custom:
            "Custom command"
        }
    }

    var opensInsideBlink: Bool {
        self == .blinkNeovim
    }

    func command(path: String, line: Int? = nil, column: Int? = nil, customTemplate: String = "") -> String {
        let safeLine = max(line ?? 1, 1)
        let safeColumn = max(column ?? 1, 1)
        let location = line == nil && column == nil
            ? NvimLauncher.shellQuote(path)
            : NvimLauncher.shellQuote("\(path):\(safeLine):\(safeColumn)")

        switch self {
        case .blinkNeovim:
            return NvimLauncher.command(path: path, line: line, column: column)
        case .cursor:
            return "cursor \(location)"
        case .zed:
            return "zed \(location)"
        case .vsCode:
            return "code --goto \(location)"
        case .custom:
            return FileEditorLauncher.renderCustomCommand(
                template: customTemplate,
                path: path,
                line: safeLine,
                column: safeColumn
            )
        }
    }

    private static func renderCustomCommand(
        template: String,
        path: String,
        line: Int,
        column: Int
    ) -> String {
        let effectiveTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "open {path}"
            : template

        return effectiveTemplate
            .replacingOccurrences(of: "{path}", with: NvimLauncher.shellQuote(path))
            .replacingOccurrences(of: "{line}", with: "\(line)")
            .replacingOccurrences(of: "{column}", with: "\(column)")
    }
}

private struct BlinkNvimPlugin {
    let directoryName: String
    let repositoryURL: String
}

enum NvimLauncher {
    private static let pluginCatalog: [String: BlinkNvimPlugin] = [
        "tokyonight": .init(directoryName: "tokyonight.nvim", repositoryURL: "https://github.com/folke/tokyonight.nvim.git"),
        "catppuccin": .init(directoryName: "catppuccin.nvim", repositoryURL: "https://github.com/catppuccin/nvim.git"),
        "rose-pine": .init(directoryName: "rose-pine.nvim", repositoryURL: "https://github.com/rose-pine/neovim.git"),
        "kanagawa": .init(directoryName: "kanagawa.nvim", repositoryURL: "https://github.com/rebelot/kanagawa.nvim.git"),
        "gruvbox": .init(directoryName: "gruvbox.nvim", repositoryURL: "https://github.com/ellisonleao/gruvbox.nvim.git"),
        "everforest": .init(directoryName: "everforest.nvim", repositoryURL: "https://github.com/neanias/everforest-nvim.git"),
        "github-theme": .init(directoryName: "github-nvim-theme", repositoryURL: "https://github.com/projekt0n/github-nvim-theme.git"),
        "dracula": .init(directoryName: "dracula.vim", repositoryURL: "https://github.com/dracula/vim.git"),
    ]

    private static let pluginLoadOrder = [
        "tokyonight",
        "catppuccin",
        "rose-pine",
        "kanagawa",
        "gruvbox",
        "everforest",
        "github-theme",
        "dracula",
    ]

    private static var pluginPrefetchStarted = false

    static func command(theme: TerminalTheme? = nil) -> String {
        syncRuntime(theme: theme, backgroundOpacity: currentBlinkBackgroundOpacity())
        let commandPath = shellQuote(wrapperCommandPath() ?? "nvim")
        return "env EDITOR=\(commandPath) VISUAL=\(commandPath) \(commandPath)"
    }

    static func command(theme: TerminalTheme? = nil, path: String, line: Int? = nil, column: Int? = nil) -> String {
        var command = command(theme: theme)

        if let line {
            command += " +\(line)"
        }

        command += " \(shellQuote(path))"
        return command
    }

    static func editorCommand(theme: TerminalTheme? = nil) -> String {
        syncRuntime(theme: theme, backgroundOpacity: currentBlinkBackgroundOpacity())
        return wrapperCommandPath() ?? "nvim"
    }

    static func syncRuntime(theme: TerminalTheme?, backgroundOpacity: Double) {
        let fileManager = FileManager.default
        let runtimeURL = runtimeDirectoryURL()
        let pluginsURL = runtimeURL.appendingPathComponent("plugins", isDirectory: true)
        let binURL = runtimeURL.appendingPathComponent("bin", isDirectory: true)
        let stateURL = runtimeURL.appendingPathComponent("state", isDirectory: true)
        let initURL = runtimeURL.appendingPathComponent("init.lua")
        let themeURL = runtimeURL.appendingPathComponent("blink-theme.lua")

        do {
            try fileManager.createDirectory(at: runtimeURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: pluginsURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: binURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: stateURL, withIntermediateDirectories: true)
            try initContents(
                themeURL: themeURL,
                pluginsURL: pluginsURL,
                pluginDirectoryNames: pluginLoadOrder.compactMap { pluginCatalog[$0]?.directoryName }
            ).write(to: initURL, atomically: true, encoding: .utf8)
            try themeContents(theme: theme, backgroundOpacity: backgroundOpacity)
                .write(to: themeURL, atomically: true, encoding: .utf8)
            try writeWrapperScripts(into: binURL, initURL: initURL, stateURL: stateURL)
        } catch {
            print("[NvimLauncher] Failed to sync runtime: \(error)")
        }

        if let theme, let plugin = plugin(for: theme.name) {
            ensurePluginInstalled(plugin, in: pluginsURL)
        }

        prefetchPluginsIfNeeded(into: pluginsURL)
    }

    static func wrapperBinPath() -> String? {
        let runtimeURL = runtimeDirectoryURL()
        let binURL = runtimeURL.appendingPathComponent("bin", isDirectory: true)
        let stateURL = runtimeURL.appendingPathComponent("state", isDirectory: true)
        let initURL = runtimeURL.appendingPathComponent("init.lua")

        do {
            try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)
            try writeWrapperScripts(into: binURL, initURL: initURL, stateURL: stateURL)
            return binURL.path
        } catch {
            print("[NvimLauncher] Failed to prepare wrapper bin: \(error)")
            return nil
        }
    }

    static func wrapperCommandPath() -> String? {
        guard let binPath = wrapperBinPath() else { return nil }
        return (binPath as NSString).appendingPathComponent("nvim")
    }

    static func resolvedNvimBinaryPath() -> String? {
        let fileManager = FileManager.default
        let inheritedPathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let fallbackEntries = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]

        var seen = Set<String>()
        for entry in inheritedPathEntries + fallbackEntries {
            guard seen.insert(entry).inserted else { continue }
            let candidate = (entry as NSString).appendingPathComponent("nvim")
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func currentBlinkBackgroundOpacity() -> Double {
        let defaults = UserDefaults.standard
        let hasWallpaper = defaults.string(forKey: "blink.backgroundImage") != nil
        if hasWallpaper, defaults.object(forKey: "blink.backgroundOpacity") != nil {
            return defaults.double(forKey: "blink.backgroundOpacity")
        }
        return 1.0
    }

    private static func runtimeDirectoryURL() -> URL {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return cachesURL.appendingPathComponent("blink-nvim", isDirectory: true)
    }

    private static func initContents(
        themeURL: URL,
        pluginsURL: URL,
        pluginDirectoryNames: [String]
    ) -> String {
        let escapedThemePath = luaStringLiteral(themeURL.path)
        let escapedPluginsPath = luaStringLiteral(pluginsURL.path)
        let pluginNamesLua = pluginDirectoryNames
            .map { "\"\(luaStringLiteral($0))\"" }
            .joined(separator: ", ")

        return """
        local config_dir = vim.fn.stdpath("config")
        local init_lua = config_dir .. "/init.lua"
        local init_vim = config_dir .. "/init.vim"
        local blink_theme = "\(escapedThemePath)"
        local blink_plugins = "\(escapedPluginsPath)"
        local plugin_directories = { \(pluginNamesLua) }

        local function ensure_blink_plugin_runtime()
          if vim.fn.isdirectory(blink_plugins) == 1 then
            for _, directory in ipairs(plugin_directories) do
              local plugin_path = blink_plugins .. "/" .. directory
              if vim.fn.isdirectory(plugin_path) == 1 then
                vim.opt.runtimepath:prepend(plugin_path)
              end
            end
          end
        end

        local function safe_dofile(path)
          local ok, err = pcall(dofile, path)
          if not ok then
            vim.schedule(function()
              vim.notify("Blink failed to source " .. path .. "\\n" .. err, vim.log.levels.WARN)
            end)
          end
        end

        local function safe_source(path)
          local ok, err = pcall(vim.cmd, "silent source " .. vim.fn.fnameescape(path))
          if not ok then
            vim.schedule(function()
              vim.notify("Blink failed to source " .. path .. "\\n" .. err, vim.log.levels.WARN)
            end)
          end
        end

        ensure_blink_plugin_runtime()

        if vim.fn.filereadable(init_lua) == 1 then
          safe_dofile(init_lua)
        end
        if vim.fn.filereadable(init_vim) == 1 then
          safe_source(init_vim)
        end

        if vim.fn.filereadable(blink_theme) == 1 then
          ensure_blink_plugin_runtime()
          vim.o.termguicolors = true
          safe_dofile(blink_theme)
        end
        """
    }

    private static func themeContents(theme: TerminalTheme?, backgroundOpacity: Double) -> String {
        guard let theme else {
            return "vim.o.termguicolors = true\n"
        }

        let transparent = backgroundOpacity < 0.999
        let pluginSetup = officialThemeLua(for: theme.name, transparent: transparent)
        let fallback = fallbackThemeLua(for: theme, transparent: transparent)
        let postThemeOverrides = postThemeOverrideLua(for: theme, transparent: transparent)

        return """
        -- Blink Neovim theme runtime v2
        vim.o.termguicolors = true
        local blink_applying = false

        local function apply_blink_theme()
          if blink_applying then
            return
          end

          blink_applying = true
          local applied = false
        \(pluginSetup.indentedLua(by: 2))
          if not applied then
        \(fallback.indentedLua(by: 4))
          end
        \(postThemeOverrides.indentedLua(by: 2))
          blink_applying = false
        end

        apply_blink_theme()

        local blink_group = vim.api.nvim_create_augroup("BlinkThemeRuntime", { clear = true })
        local function schedule_blink_theme(delay)
          vim.defer_fn(function()
            if blink_applying then
              return
            end
            pcall(apply_blink_theme)
          end, delay)
        end

        vim.api.nvim_create_autocmd({ "VimEnter", "UIEnter" }, {
          group = blink_group,
          callback = function()
            vim.schedule(apply_blink_theme)
          end,
        })
        vim.api.nvim_create_autocmd("User", {
          group = blink_group,
          pattern = { "LazyDone", "VeryLazy", "LazyVimStarted" },
          callback = function()
            vim.schedule(apply_blink_theme)
          end,
        })
        vim.api.nvim_create_autocmd("ColorScheme", {
          group = blink_group,
          callback = function()
            if blink_applying then
              return
            end
            vim.schedule(apply_blink_theme)
          end,
        })

        schedule_blink_theme(10)
        schedule_blink_theme(100)
        schedule_blink_theme(300)
        schedule_blink_theme(1000)
        """
    }

    private static func officialThemeLua(for themeName: String, transparent: Bool) -> String {
        let transparentValue = luaBool(transparent)

        switch themeName {
        case "TokyoNight":
            return """
            applied = pcall(function()
              local tokyonight = require("tokyonight")
              tokyonight.setup({ style = "storm", transparent = \(transparentValue) })
              vim.cmd.colorscheme("tokyonight")
            end)
            """
        case "TokyoNight Day":
            return """
            applied = pcall(function()
              local tokyonight = require("tokyonight")
              tokyonight.setup({ style = "day", transparent = \(transparentValue) })
              vim.cmd.colorscheme("tokyonight")
            end)
            """
        case "Catppuccin Mocha":
            return """
            applied = pcall(function()
              local catppuccin = require("catppuccin")
              catppuccin.setup({ flavour = "mocha", transparent_background = \(transparentValue) })
              vim.cmd.colorscheme("catppuccin")
            end)
            """
        case "Catppuccin Latte":
            return """
            applied = pcall(function()
              local catppuccin = require("catppuccin")
              catppuccin.setup({ flavour = "latte", transparent_background = \(transparentValue) })
              vim.cmd.colorscheme("catppuccin")
            end)
            """
        case "Rose Pine":
            return """
            applied = pcall(function()
              local rose_pine = require("rose-pine")
              rose_pine.setup({ variant = "main", styles = { transparency = \(transparentValue) } })
              vim.cmd.colorscheme("rose-pine")
            end)
            """
        case "Rose Pine Dawn":
            return """
            applied = pcall(function()
              local rose_pine = require("rose-pine")
              rose_pine.setup({ variant = "dawn", styles = { transparency = \(transparentValue) } })
              vim.cmd.colorscheme("rose-pine-dawn")
            end)
            """
        case "Kanagawa Wave":
            return """
            applied = pcall(function()
              local kanagawa = require("kanagawa")
              kanagawa.setup({ theme = "wave", transparent = \(transparentValue) })
              vim.cmd.colorscheme("kanagawa")
            end)
            """
        case "Kanagawa Lotus":
            return """
            applied = pcall(function()
              local kanagawa = require("kanagawa")
              kanagawa.setup({ theme = "lotus", transparent = \(transparentValue) })
              vim.cmd.colorscheme("kanagawa")
            end)
            """
        case "Gruvbox Dark":
            return """
            applied = pcall(function()
              local gruvbox = require("gruvbox")
              gruvbox.setup({ transparent_mode = \(transparentValue) })
              vim.o.background = "dark"
              vim.cmd.colorscheme("gruvbox")
            end)
            """
        case "Everforest Dark Hard":
            return """
            applied = pcall(function()
              vim.g.everforest_background = "hard"
              vim.g.everforest_transparent_background = \(transparent ? "1" : "0")
              vim.o.background = "dark"
              vim.cmd.colorscheme("everforest")
            end)
            """
        case "GitHub Dark Default":
            return """
            applied = pcall(function()
              local github_theme = require("github-theme")
              github_theme.setup({ options = { transparent = \(transparentValue) } })
              vim.cmd.colorscheme("github_dark_default")
            end)
            """
        case "GitHub Light Default":
            return """
            applied = pcall(function()
              local github_theme = require("github-theme")
              github_theme.setup({ options = { transparent = \(transparentValue) } })
              vim.cmd.colorscheme("github_light_default")
            end)
            """
        case "Dracula":
            return """
            applied = pcall(function()
              vim.g.dracula_transparent_bg = \(transparentValue)
              vim.cmd.colorscheme("dracula")
            end)
            """
        default:
            return ""
        }
    }

    private static func fallbackThemeLua(for theme: TerminalTheme, transparent: Bool) -> String {
        let accent = theme.cursorColor.lowercased() != theme.foreground.lowercased()
            ? theme.cursorColor
            : theme.palette[4]
        let normalBackground = transparent ? "none" : theme.background
        let floatBackground = transparent ? "none" : theme.palette[0]
        let isLightBackground = isLight(theme)

        let groups: [(String, String)] = [
            ("Normal", "fg = '\(theme.foreground)', bg = '\(normalBackground)'"),
            ("NormalNC", "fg = '\(theme.foreground)', bg = '\(normalBackground)'"),
            ("NormalFloat", "fg = '\(theme.foreground)', bg = '\(floatBackground)'"),
            ("FloatBorder", "fg = '\(theme.palette[8])', bg = '\(floatBackground)'"),
            ("CursorLine", "bg = '\(theme.selectionBackground)'"),
            ("CursorLineNr", "fg = '\(accent)', bold = true"),
            ("LineNr", "fg = '\(theme.palette[8])'"),
            ("Comment", "fg = '\(theme.palette[8])', italic = true"),
            ("Constant", "fg = '\(theme.palette[3])'"),
            ("String", "fg = '\(theme.palette[2])'"),
            ("Identifier", "fg = '\(theme.palette[6])'"),
            ("Function", "fg = '\(theme.palette[4])'"),
            ("Statement", "fg = '\(theme.palette[5])'"),
            ("PreProc", "fg = '\(theme.palette[5])'"),
            ("Type", "fg = '\(theme.palette[4])'"),
            ("Special", "fg = '\(theme.palette[6])'"),
            ("DiagnosticError", "fg = '\(theme.palette[1])'"),
            ("DiagnosticWarn", "fg = '\(theme.palette[3])'"),
            ("DiagnosticInfo", "fg = '\(theme.palette[4])'"),
            ("DiagnosticHint", "fg = '\(theme.palette[6])'"),
            ("Visual", "bg = '\(theme.selectionBackground)'"),
            ("Pmenu", "fg = '\(theme.foreground)', bg = '\(floatBackground)'"),
            ("PmenuSel", "fg = '\(theme.background)', bg = '\(accent)'"),
            ("StatusLine", "fg = '\(theme.foreground)', bg = '\(floatBackground)'"),
            ("StatusLineNC", "fg = '\(theme.palette[8])', bg = '\(floatBackground)'"),
            ("WinSeparator", "fg = '\(theme.palette[8])'"),
        ]

        let highlightLines = groups.map {
            "vim.api.nvim_set_hl(0, '\($0.0)', { \($0.1) })"
        }.joined(separator: "\n")

        let terminalLines = theme.palette.enumerated().map {
            "vim.g.terminal_color_\($0.offset) = '\($0.element)'"
        }.joined(separator: "\n")

        return """
        vim.g.colors_name = "blink_current"
        vim.o.background = "\(isLightBackground ? "light" : "dark")"
        \(terminalLines)
        \(highlightLines)
        """
    }

    private static func postThemeOverrideLua(for theme: TerminalTheme, transparent: Bool) -> String {
        let baseBackground = transparent ? "none" : theme.background
        let floatBackground = transparent ? "none" : theme.palette[0]
        let lineNumberBackground = transparent ? "none" : baseBackground
        let groups: [(String, String)] = [
            ("Normal", "fg = '\(theme.foreground)', bg = '\(baseBackground)'"),
            ("NormalNC", "fg = '\(theme.foreground)', bg = '\(baseBackground)'"),
            ("NormalFloat", "fg = '\(theme.foreground)', bg = '\(floatBackground)'"),
            ("FloatBorder", "fg = '\(theme.palette[8])', bg = '\(floatBackground)'"),
            ("Pmenu", "fg = '\(theme.foreground)', bg = '\(floatBackground)'"),
            ("StatusLine", "fg = '\(theme.foreground)', bg = '\(floatBackground)'"),
            ("StatusLineNC", "fg = '\(theme.palette[8])', bg = '\(floatBackground)'"),
            ("WinBar", "fg = '\(theme.foreground)', bg = '\(floatBackground)'"),
            ("WinBarNC", "fg = '\(theme.palette[8])', bg = '\(floatBackground)'"),
            ("LineNr", "fg = '\(theme.palette[8])', bg = '\(lineNumberBackground)'"),
            ("CursorLineNr", "bg = '\(lineNumberBackground)'"),
            ("SignColumn", "bg = '\(lineNumberBackground)'"),
            ("FoldColumn", "bg = '\(lineNumberBackground)'"),
            ("EndOfBuffer", "fg = '\(theme.palette[8])', bg = '\(baseBackground)'"),
            ("NonText", "fg = '\(theme.palette[8])', bg = '\(baseBackground)'"),
            ("MsgArea", "bg = '\(baseBackground)'"),
            ("WinSeparator", "fg = '\(theme.palette[8])', bg = '\(baseBackground)'"),
            ("VertSplit", "fg = '\(theme.palette[8])', bg = '\(baseBackground)'"),
        ]

        let highlightLines = groups.map {
            "vim.api.nvim_set_hl(0, '\($0.0)', { \($0.1) })"
        }.joined(separator: "\n")

        return """
        \(highlightLines)
        """
    }

    private static func plugin(for themeName: String) -> BlinkNvimPlugin? {
        switch themeName {
        case "TokyoNight", "TokyoNight Day":
            return pluginCatalog["tokyonight"]
        case "Catppuccin Mocha", "Catppuccin Latte":
            return pluginCatalog["catppuccin"]
        case "Rose Pine", "Rose Pine Dawn":
            return pluginCatalog["rose-pine"]
        case "Kanagawa Wave", "Kanagawa Lotus":
            return pluginCatalog["kanagawa"]
        case "Gruvbox Dark":
            return pluginCatalog["gruvbox"]
        case "Everforest Dark Hard":
            return pluginCatalog["everforest"]
        case "GitHub Dark Default", "GitHub Light Default":
            return pluginCatalog["github-theme"]
        case "Dracula":
            return pluginCatalog["dracula"]
        default:
            return nil
        }
    }

    private static func ensurePluginInstalled(_ plugin: BlinkNvimPlugin, in pluginsURL: URL) {
        let destinationURL = pluginsURL.appendingPathComponent(plugin.directoryName, isDirectory: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return
        }

        guard let gitPath = resolvedExecutable(named: "git") else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["clone", "--depth=1", plugin.repositoryURL, destinationURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("[NvimLauncher] Failed to install \(plugin.directoryName): \(error)")
        }
    }

    private static func prefetchPluginsIfNeeded(into pluginsURL: URL) {
        guard !pluginPrefetchStarted else { return }
        pluginPrefetchStarted = true

        let plugins = pluginLoadOrder.compactMap { pluginCatalog[$0] }
        DispatchQueue.global(qos: .utility).async {
            for plugin in plugins {
                ensurePluginInstalled(plugin, in: pluginsURL)
            }
        }
    }

    private static func writeWrapperScripts(into binURL: URL, initURL: URL, stateURL: URL) throws {
        let realNvimPath = resolvedNvimBinaryPath() ?? "/opt/homebrew/bin/nvim"
        let initPath = initURL.path
        let statePath = stateURL.path
        let wrapperContents = """
        #!/bin/sh
        REAL_NVIM="${BLINK_REAL_NVIM:-\(realNvimPath)}"
        export XDG_STATE_HOME="${XDG_STATE_HOME:-\(statePath)}"
        if [ ! -x "$REAL_NVIM" ]; then
          echo "Blink could not find Neovim at $REAL_NVIM" >&2
          exit 127
        fi
        exec "$REAL_NVIM" -u \(shellQuote(initPath)) "$@"
        """

        let nvimURL = binURL.appendingPathComponent("nvim")
        let vimURL = binURL.appendingPathComponent("vim")

        try wrapperContents.write(to: nvimURL, atomically: true, encoding: .utf8)
        try wrapperContents.write(to: vimURL, atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nvimURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: vimURL.path)
    }

    private static func resolvedExecutable(named name: String) -> String? {
        let fileManager = FileManager.default
        let inheritedPathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let fallbackEntries = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]

        var seen = Set<String>()
        for entry in inheritedPathEntries + fallbackEntries {
            guard seen.insert(entry).inserted else { continue }
            let candidate = (entry as NSString).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func isLight(_ theme: TerminalTheme) -> Bool {
        guard let components = Color.hexComponents(theme.background) else {
            return false
        }
        let luminance = 0.299 * components.red + 0.587 * components.green + 0.114 * components.blue
        return luminance > 0.5
    }

    private static func luaBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static func luaStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private extension String {
    func indentedLua(by spaces: Int) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }
}
