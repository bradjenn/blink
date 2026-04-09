import SwiftUI
import AppKit

struct TerminalSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    let ghosttyApp: GhosttyApp

    @State private var monospaceFonts: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("Terminal")
                .font(Fonts.primary(size: 18, weight: .bold, family: store.uiFontFamily))
                .foregroundStyle(theme.text)

            fontFamilySection
            fontSizeSection
            cursorStyleSection
            cursorBlinkSection
            shellSection
            spotifyCommandSection

            Spacer(minLength: 0)
        }
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
        .task { monospaceFonts = Self.loadMonospaceFonts() }
    }

    private var fontFamilySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Font family")
                .font(Fonts.primary(size: 14, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(theme.text)
            Text("Monospace font used in the terminal")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)

            StyledDropdown(
                selection: store.fontFamily,
                options: ["MesloLGS Nerd Font Mono"] + monospaceFonts,
                label: { $0 },
                onChange: {
                    store.fontFamily = $0
                    updateTerminalConfig()
                },
                fontPreview: true
            )
            .frame(maxWidth: 300)
        }
    }

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Font size")
                .font(Fonts.primary(size: 14, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(theme.text)
            Text("Size in points for terminal text")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)

            StyledStepper(
                value: Int(store.fontSize),
                range: 10...32,
                label: "\(Int(store.fontSize))pt",
                onChange: {
                    store.fontSize = CGFloat($0)
                    updateTerminalConfig()
                }
            )
        }
    }

    private var cursorStyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cursor style")
                .font(Fonts.primary(size: 14, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(theme.text)
            Text("Default shape of the terminal cursor.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)

            StyledSegmentPicker(
                options: CursorStyle.allCases,
                selection: store.cursorStyle,
                label: { $0.displayName },
                onChange: {
                    store.cursorStyle = $0
                    updateTerminalConfig()
                }
            )
        }
    }

    private var cursorBlinkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cursor blink")
                .font(Fonts.primary(size: 14, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(theme.text)
            Text("Blink the terminal cursor. This applies to existing terminal tabs too.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)

            StyledSegmentPicker(
                options: [false, true],
                selection: store.cursorBlink,
                label: { $0 ? "On" : "Off" },
                onChange: {
                    store.cursorBlink = $0
                    updateTerminalConfig()
                }
            )
        }
    }

    private var shellSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shell")
                .font(Fonts.primary(size: 14, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(theme.text)
            Text("Program to run in new terminal tabs (changes apply to new tabs)")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)

            HStack(spacing: 8) {
                @Bindable var store = store
                StyledTextField(text: $store.shell, placeholder: "Shell path")
                    .frame(maxWidth: 300)

                if store.shell != AppStore.defaultShell {
                    Button("Reset") {
                        store.shell = AppStore.defaultShell
                    }
                    .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                    .foregroundStyle(theme.accent)
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }
        }
    }

    private var spotifyCommandSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spotify now playing")
                .font(Fonts.primary(size: 14, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(theme.text)
            Text("Show the current track in the status line and sidebar. Click it to open Spotify in a full-width tab.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)
            Text("Requires spotatui. The Spotify tab uses the current Blink theme when it opens.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)
            Text("If you change Blink themes while Spotify is open, reopen the tab to refresh its colors.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)
            Text("brew install spotatui")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.textDim)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )

            StyledSegmentPicker(
                options: [false, true],
                selection: store.spotifyEnabled,
                label: { $0 ? "On" : "Off" },
                onChange: { store.spotifyEnabled = $0 }
            )
        }
    }

    private func updateTerminalConfig() {
        if let termTheme = themeManager.activeTerminalTheme {
            let effectiveOpacity = store.hasWallpaper ? store.backgroundOpacity : 1.0
            ghosttyApp.updateConfig(
                terminalTheme: termTheme,
                backgroundOpacity: effectiveOpacity,
                fontFamily: store.fontFamily,
                fontSize: store.fontSize,
                cursorStyle: store.cursorStyle,
                cursorBlink: store.cursorBlink
            )
        }
    }

    private static func loadMonospaceFonts() -> [String] {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter { family in
            guard let members = manager.availableMembers(ofFontFamily: family),
                  let first = members.first,
                  let fontName = first[0] as? String,
                  let font = NSFont(name: fontName, size: 13) else { return false }
            return font.isFixedPitch
        }
        .filter { $0 != "MesloLGS Nerd Font Mono" }
        .sorted()
    }
}
