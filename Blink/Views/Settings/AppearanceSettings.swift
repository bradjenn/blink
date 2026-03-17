import SwiftUI
import AppKit

struct AppearanceSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    let ghosttyApp: GhosttyApp

    private let wallpaperColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Appearance")
                    .font(Fonts.primary(size: 18, weight: .bold))
                    .foregroundStyle(theme.text)

                // Theme section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme")
                        .font(Fonts.primary(size: 14, weight: .medium))
                        .foregroundStyle(theme.text)
                    Text("Color scheme for the app and terminal")
                        .font(Fonts.primary(size: 12))
                        .foregroundStyle(theme.textMuted)

                    Button {
                        store.presentThemePicker()
                    } label: {
                        HStack(spacing: 10) {
                            Text(store.theme)
                                .font(Fonts.primary(size: 13))
                                .foregroundStyle(theme.text)

                            // Color palette preview
                            if let parsed = themeManager.activeTerminalTheme {
                                HStack(spacing: 3) {
                                    Circle().fill(Color(hex: parsed.background)).frame(width: 12, height: 12)
                                        .overlay { Circle().stroke(theme.border, lineWidth: 0.5) }
                                    Circle().fill(Color(hex: parsed.foreground)).frame(width: 12, height: 12)
                                    Circle().fill(Color(hex: parsed.palette[1])).frame(width: 12, height: 12)
                                    Circle().fill(Color(hex: parsed.palette[2])).frame(width: 12, height: 12)
                                    Circle().fill(Color(hex: parsed.palette[4])).frame(width: 12, height: 12)
                                    Circle().fill(Color(hex: parsed.palette[5])).frame(width: 12, height: 12)
                                }
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(theme.textDim)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(theme.accent.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(theme.accent.opacity(0.2), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }

                // Background image section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Background image")
                        .font(Fonts.primary(size: 14, weight: .medium))
                        .foregroundStyle(theme.text)
                    Text("Show a wallpaper behind the content area")
                        .font(Fonts.primary(size: 12))
                        .foregroundStyle(theme.textMuted)

                    LazyVGrid(columns: wallpaperColumns, spacing: 12) {
                        WallpaperCard(
                            name: "None",
                            filename: nil,
                            isSelected: store.backgroundImage == nil,
                            onSelect: { setWallpaper(nil) }
                        )

                        ForEach(WallpaperPreset.all) { preset in
                            WallpaperCard(
                                name: preset.name,
                                filename: preset.filename,
                                isSelected: store.backgroundImage == preset.id,
                                onSelect: { setWallpaper(preset.id) }
                            )
                        }

                        WallpaperCard(
                            name: "Custom...",
                            filename: nil,
                            isSelected: store.backgroundImage != nil
                                && !(store.backgroundImage!.hasPrefix("preset:")),
                            onSelect: { pickCustomWallpaper() }
                        )
                    }
                    .padding(.top, 4)
                }

                // Background opacity section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Background opacity")
                        .font(Fonts.primary(size: 14, weight: .medium))
                        .foregroundStyle(theme.text)
                    Text("How translucent the terminal overlay is (lower = more wallpaper visible)")
                        .font(Fonts.primary(size: 12))
                        .foregroundStyle(theme.textMuted)

                    HStack(spacing: 12) {
                        @Bindable var store = store
                        Slider(value: $store.backgroundOpacity, in: 0.1...1.0, step: 0.05)
                            .disabled(!store.hasWallpaper)
                            .tint(theme.accent)
                            .onChange(of: store.backgroundOpacity) { _, newValue in
                                store.setBackgroundOpacity(newValue)
                                if let termTheme = themeManager.activeTerminalTheme {
                                    let effectiveOpacity = store.hasWallpaper ? newValue : 1.0
                                    ghosttyApp.updateConfig(
                                        terminalTheme: termTheme,
                                        backgroundOpacity: effectiveOpacity
                                    )
                                }
                            }

                        Text("\(Int(store.backgroundOpacity * 100))%")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.textMuted)
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                // Background blur section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Background blur")
                        .font(Fonts.primary(size: 14, weight: .medium))
                        .foregroundStyle(theme.text)
                    Text("Apply gaussian blur to the wallpaper image")
                        .font(Fonts.primary(size: 12))
                        .foregroundStyle(theme.textMuted)

                    HStack(spacing: 12) {
                        @Bindable var store = store
                        Slider(value: $store.backgroundBlur, in: 0...32, step: 1)
                            .disabled(!store.hasWallpaper)
                            .tint(theme.accent)
                            .onChange(of: store.backgroundBlur) { _, newValue in
                                store.setBackgroundBlur(newValue)
                            }

                        Text("\(Int(store.backgroundBlur))px")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.textMuted)
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    /// Set wallpaper and update terminal opacity accordingly.
    private func setWallpaper(_ image: String?) {
        store.setBackgroundImage(image)
        updateTerminalOpacity()
    }

    private func pickCustomWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            store.setBackgroundImage(url.path)
            updateTerminalOpacity()
        }
    }

    /// Sync terminal background-opacity: use store value when wallpaper is set, 1.0 otherwise.
    private func updateTerminalOpacity() {
        if let termTheme = themeManager.activeTerminalTheme {
            let effectiveOpacity = store.hasWallpaper ? store.backgroundOpacity : 1.0
            ghosttyApp.updateConfig(terminalTheme: termTheme, backgroundOpacity: effectiveOpacity)
        }
    }
}
