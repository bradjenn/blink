import SwiftUI
import AppKit

struct TerminalSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    let ghosttyApp: GhosttyApp

    @State private var monospaceFonts: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Terminal")
                    .font(Fonts.primary(size: 18, weight: .bold))
                    .foregroundStyle(theme.text)

                fontFamilySection
                fontSizeSection
                cursorStyleSection
                shellSection

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .task { monospaceFonts = Self.loadMonospaceFonts() }
    }

    private var fontFamilySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Font family")
                .font(Fonts.primary(size: 14, weight: .medium))
                .foregroundStyle(theme.text)
            Text("Monospace font used in the terminal")
                .font(Fonts.primary(size: 12))
                .foregroundStyle(theme.textMuted)

            Picker("", selection: Binding(
                get: { store.fontFamily },
                set: { newValue in
                    store.fontFamily = newValue
                    updateTerminalConfig()
                }
            )) {
                Text("MesloLGS Nerd Font Mono").tag("MesloLGS Nerd Font Mono")
                if !monospaceFonts.isEmpty {
                    Divider()
                    ForEach(monospaceFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: 300)
        }
    }

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Font size")
                .font(Fonts.primary(size: 14, weight: .medium))
                .foregroundStyle(theme.text)
            Text("Size in points for terminal text")
                .font(Fonts.primary(size: 12))
                .foregroundStyle(theme.textMuted)

            HStack(spacing: 12) {
                @Bindable var store = store
                Stepper(
                    "\(Int(store.fontSize))pt",
                    value: $store.fontSize,
                    in: 10...32,
                    step: 1
                )
                .font(Fonts.primary(size: 13))
                .foregroundStyle(theme.text)
                .onChange(of: store.fontSize) {
                    updateTerminalConfig()
                }
            }
        }
    }

    private var cursorStyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cursor style")
                .font(Fonts.primary(size: 14, weight: .medium))
                .foregroundStyle(theme.text)
            Text("Shape of the terminal cursor")
                .font(Fonts.primary(size: 12))
                .foregroundStyle(theme.textMuted)

            Picker("", selection: Binding(
                get: { store.cursorStyle },
                set: { newValue in
                    store.cursorStyle = newValue
                    updateTerminalConfig()
                }
            )) {
                ForEach(CursorStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
        }
    }

    private var shellSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shell")
                .font(Fonts.primary(size: 14, weight: .medium))
                .foregroundStyle(theme.text)
            Text("Program to run in new terminal tabs (changes apply to new tabs)")
                .font(Fonts.primary(size: 12))
                .foregroundStyle(theme.textMuted)

            HStack(spacing: 8) {
                @Bindable var store = store
                TextField("Shell path", text: $store.shell)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: 300)

                if store.shell != AppStore.defaultShell {
                    Button("Reset") {
                        store.shell = AppStore.defaultShell
                    }
                    .font(Fonts.primary(size: 12))
                    .foregroundStyle(theme.accent)
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }
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
                cursorStyle: store.cursorStyle
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
