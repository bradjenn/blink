import SwiftUI
import AppKit

struct AppearanceSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    let ghosttyApp: GhosttyApp

    @State private var showThemePicker = false

    private let wallpaperColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ZStack {
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
                            showThemePicker = true
                        } label: {
                            HStack {
                                Text(store.theme)
                                    .font(Fonts.primary(size: 13))
                                    .foregroundStyle(theme.text)
                                Spacer()
                                Text("Change")
                                    .font(Fonts.primary(size: 12))
                                    .foregroundStyle(theme.accent)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(theme.bg2)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
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
                                onSelect: { store.setBackgroundImage(nil) }
                            )

                            ForEach(WallpaperPreset.all) { preset in
                                WallpaperCard(
                                    name: preset.name,
                                    filename: preset.filename,
                                    isSelected: store.backgroundImage == preset.id,
                                    onSelect: { store.setBackgroundImage(preset.id) }
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
                            Slider(
                                value: Binding(
                                    get: { store.backgroundOpacity },
                                    set: { newValue in
                                        store.setBackgroundOpacity(newValue)
                                        if let termTheme = themeManager.activeTerminalTheme {
                                            ghosttyApp.updateConfig(
                                                terminalTheme: termTheme,
                                                backgroundOpacity: newValue
                                            )
                                        }
                                    }
                                ),
                                in: 0.1...1.0,
                                step: 0.05
                            )
                            .disabled(!store.hasWallpaper)
                            .tint(theme.accent)

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
                            Slider(
                                value: Binding(
                                    get: { store.backgroundBlur },
                                    set: { store.setBackgroundBlur($0) }
                                ),
                                in: 0...32,
                                step: 1
                            )
                            .disabled(!store.hasWallpaper)
                            .tint(theme.accent)

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

            if showThemePicker {
                ThemePicker(
                    ghosttyApp: ghosttyApp,
                    onDismiss: { showThemePicker = false }
                )
            }
        }
    }

    private func pickCustomWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            store.setBackgroundImage(url.path)
        }
    }
}
