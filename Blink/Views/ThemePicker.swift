import SwiftUI

struct ThemePicker: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    let ghosttyApp: GhosttyApp
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var committedThemeName = ""
    @State private var didCommitSelection = false
    @State private var terminalPreviewTask: Task<Void, Never>?
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

    private var effectiveBackgroundOpacity: Double {
        store.hasWallpaper ? store.backgroundOpacity : 1.0
    }

    private var panelBackground: some ShapeStyle {
        if store.hasWallpaper {
            AnyShapeStyle(theme.bg.opacity(store.backgroundOpacity))
        } else {
            AnyShapeStyle(theme.bg.opacity(0.97))
        }
    }

    private func requestSearchFocus() {
        searchFocused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            searchFocused = true
        }
    }

    private func moveSelection(by delta: Int) {
        guard !allItems.isEmpty else { return }
        let count = allItems.count
        selectedIndex = (selectedIndex + delta + count) % count
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { dismissPicker() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Dismiss")

            VStack(spacing: 0) {
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

                theme.border.frame(height: 1)

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
                    .onAppear {
                        scrollSelection(in: proxy, animated: false)
                    }
                    .onChange(of: selectedIndex) {
                        scrollSelection(in: proxy)
                    }
                }

                theme.border.frame(height: 1)

                HStack(spacing: 14) {
                    hint("↑↓ j/k", label: "navigate")
                    hint("↵", label: "select")
                    hint("esc", label: "close")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 500, height: 480)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.36), radius: 22, y: 12)
            .onKeyPress(.upArrow) {
                moveSelection(by: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "jk")) { keyPress in
                guard !allItems.isEmpty else { return .ignored }

                switch keyPress.characters.lowercased() {
                case "j":
                    moveSelection(by: 1)
                    return .handled
                case "k":
                    moveSelection(by: -1)
                    return .handled
                default:
                    return .ignored
                }
            }
            .onKeyPress(.return) {
                guard allItems.indices.contains(selectedIndex) else { return .ignored }
                commitTheme(allItems[selectedIndex])
                return .handled
            }
            .onKeyPress(.escape) {
                dismissPicker()
                return .handled
            }
        }
        .onAppear {
            didCommitSelection = false
            committedThemeName = store.theme
            if let idx = allItems.firstIndex(of: store.theme) {
                selectedIndex = idx
            }
            requestSearchFocus()
            previewSelectedTheme()
        }
        .onChange(of: store.themePickerFocusRequest) {
            requestSearchFocus()
        }
        .onChange(of: searchText) {
            selectedIndex = 0
        }
        .onChange(of: allItems.map(\.self)) {
            if allItems.isEmpty {
                selectedIndex = 0
            } else {
                selectedIndex = min(selectedIndex, allItems.count - 1)
            }
            previewSelectedTheme()
        }
        .onChange(of: selectedIndex) {
            previewSelectedTheme()
        }
        .onDisappear {
            terminalPreviewTask?.cancel()
            guard !didCommitSelection else { return }
            restoreCommittedTheme()
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
            commitTheme(name)
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
            .background(isSelected ? theme.accent.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
        .id(name)
    }

    private func scrollSelection(in proxy: ScrollViewProxy, animated: Bool = true) {
        guard allItems.indices.contains(selectedIndex) else { return }
        let themeName = allItems[selectedIndex]

        DispatchQueue.main.async {
            if animated {
                withAnimation(.snappy(duration: 0.18)) {
                    proxy.scrollTo(themeName, anchor: .center)
                }
            } else {
                proxy.scrollTo(themeName, anchor: .center)
            }
        }
    }

    private func previewSelectedTheme() {
        guard allItems.indices.contains(selectedIndex) else { return }
        previewTheme(allItems[selectedIndex])
    }

    private func previewTheme(_ name: String) {
        themeManager.setTheme(name: name)
        scheduleTerminalPreview(name)
    }

    private func restoreCommittedTheme() {
        applyThemeImmediately(committedThemeName)
    }

    private func dismissPicker() {
        restoreCommittedTheme()
        onDismiss()
    }

    private func commitTheme(_ name: String) {
        didCommitSelection = true
        store.theme = name
        committedThemeName = name
        applyThemeImmediately(name)
        onDismiss()
    }

    private func scheduleTerminalPreview(_ name: String) {
        terminalPreviewTask?.cancel()
        terminalPreviewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000)
            guard !Task.isCancelled,
                  let termTheme = themeManager.previewTheme(name: name) else {
                return
            }

            ghosttyApp.updateConfig(
                terminalTheme: termTheme,
                backgroundOpacity: effectiveBackgroundOpacity,
                fontFamily: store.fontFamily,
                fontSize: store.fontSize,
                cursorStyle: store.cursorStyle,
                cursorBlink: store.cursorBlink
            )
        }
    }

    private func applyThemeImmediately(_ name: String) {
        terminalPreviewTask?.cancel()
        terminalPreviewTask = nil
        themeManager.setTheme(name: name)
        guard let termTheme = themeManager.previewTheme(name: name) else { return }
        ghosttyApp.updateConfig(
            terminalTheme: termTheme,
            backgroundOpacity: effectiveBackgroundOpacity,
            fontFamily: store.fontFamily,
            fontSize: store.fontSize,
            cursorStyle: store.cursorStyle,
            cursorBlink: store.cursorBlink
        )
    }

    private func hint(_ key: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(Fonts.primary(size: 10))
                .foregroundStyle(theme.textMuted)

            Text(label)
                .font(Fonts.primary(size: 10))
                .foregroundStyle(theme.textDim)
        }
    }
}
