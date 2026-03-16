import SwiftUI

struct ThemePicker: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    let ghosttyApp: GhosttyApp
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    /// Perceived brightness of a hex color (0 = black, 1 = white).
    private func isLightTheme(_ name: String) -> Bool {
        guard let parsed = themeManager.previewTheme(name: name),
              let c = Color.hexComponents(parsed.background) else {
            return false
        }
        // Relative luminance approximation
        let luminance = 0.299 * c.red + 0.587 * c.green + 0.114 * c.blue
        return luminance > 0.5
    }

    private func applySearch(_ names: [String]) -> [String] {
        if searchText.isEmpty { return names }
        return names.filter { $0.localizedStandardContains(searchText) }
    }

    private var filteredFavorites: [String] {
        let favs = ThemeManager.favorites.filter { themeManager.availableThemes.contains($0) }
        return applySearch(favs)
    }

    private var filteredDark: [String] {
        let nonFavs = themeManager.availableThemes.filter {
            !ThemeManager.favorites.contains($0) && !isLightTheme($0)
        }
        return applySearch(nonFavs)
    }

    private var filteredLight: [String] {
        let nonFavs = themeManager.availableThemes.filter {
            !ThemeManager.favorites.contains($0) && isLightTheme($0)
        }
        return applySearch(nonFavs)
    }

    private var allItems: [String] {
        filteredFavorites + filteredDark + filteredLight
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Dismiss")

            // Panel
            VStack(spacing: 0) {
                // Search input
                HStack(spacing: 8) {
                    Text(">")
                        .font(Fonts.primary(size: 14))
                        .foregroundStyle(theme.accent)
                    TextField("Search themes...", text: $searchText)
                        .font(Fonts.primary(size: 14))
                        .textFieldStyle(.plain)
                        .foregroundStyle(theme.text)
                        .focused($searchFocused)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Divider
                theme.border.frame(height: 1)

                // Scrollable list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if !filteredFavorites.isEmpty {
                                sectionHeader("FAVORITES")
                                ForEach(Array(filteredFavorites.enumerated()), id: \.element) { idx, name in
                                    themeRow(name: name, globalIndex: idx)
                                }
                            }

                            if !filteredDark.isEmpty {
                                sectionHeader("DARK")
                                ForEach(Array(filteredDark.enumerated()), id: \.element) { idx, name in
                                    let globalIdx = filteredFavorites.count + idx
                                    themeRow(name: name, globalIndex: globalIdx)
                                }
                            }

                            if !filteredLight.isEmpty {
                                sectionHeader("LIGHT")
                                ForEach(Array(filteredLight.enumerated()), id: \.element) { idx, name in
                                    let globalIdx = filteredFavorites.count + filteredDark.count + idx
                                    themeRow(name: name, globalIndex: globalIdx)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(width: 500, height: 450)
            .background(theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            .onKeyPress(.upArrow) {
                selectedIndex = max(0, selectedIndex - 1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                selectedIndex = min(allItems.count - 1, selectedIndex + 1)
                return .handled
            }
            .onKeyPress(.return) {
                if selectedIndex < allItems.count {
                    applyTheme(allItems[selectedIndex])
                }
                return .handled
            }
            .onKeyPress(.escape) {
                onDismiss()
                return .handled
            }
        }
        .onAppear {
            searchFocused = true
            if let idx = allItems.firstIndex(of: store.theme) {
                selectedIndex = idx
            }
        }
        .onChange(of: searchText) {
            selectedIndex = 0
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Fonts.primary(size: 11, weight: .medium))
            .foregroundStyle(theme.textDim)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func themeRow(name: String, globalIndex: Int) -> some View {
        let isSelected = globalIndex == selectedIndex
        let isCurrent = name == store.theme

        return Button {
            applyTheme(name)
        } label: {
            HStack {
                if isCurrent {
                    Text("*")
                        .font(Fonts.primary(size: 12, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 16)
                } else {
                    Color.clear.frame(width: 16, height: 1)
                }

                Text(name)
                    .font(Fonts.primary(size: 13))
                    .foregroundStyle(isSelected ? theme.text : theme.textMuted)
                    .lineLimit(1)

                Spacer()

                // Color preview dots
                if let parsed = themeManager.previewTheme(name: name) {
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: parsed.background)).frame(width: 10, height: 10)
                            .overlay { Circle().stroke(theme.border, lineWidth: 0.5) }
                        Circle().fill(Color(hex: parsed.foreground)).frame(width: 10, height: 10)
                        Circle().fill(Color(hex: parsed.palette[1])).frame(width: 10, height: 10)
                        Circle().fill(Color(hex: parsed.palette[2])).frame(width: 10, height: 10)
                        Circle().fill(Color(hex: parsed.palette[4])).frame(width: 10, height: 10)
                        Circle().fill(Color(hex: parsed.palette[5])).frame(width: 10, height: 10)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(isSelected ? theme.accent.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .id(name)
    }

    private func applyTheme(_ name: String) {
        store.theme = name
        themeManager.setTheme(name: name)
        if let termTheme = themeManager.activeTerminalTheme {
            let effectiveOpacity = store.hasWallpaper ? store.backgroundOpacity : 1.0
            ghosttyApp.updateConfig(terminalTheme: termTheme, backgroundOpacity: effectiveOpacity)
        }
        onDismiss()
    }
}
