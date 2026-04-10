import AppKit
import SwiftUI

private struct ThemePickerMetadata: Equatable {
    let isLight: Bool
    let swatches: [String]
}

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
    @State private var keyMonitor: Any?
    @State private var previewTask: Task<Void, Never>?
    @State private var preloadTask: Task<Void, Never>?
    @State private var metadataByName: [String: ThemePickerMetadata] = [:]
    @State private var filteredFavorites: [String] = []
    @State private var filteredDark: [String] = []
    @State private var filteredLight: [String] = []
    @FocusState private var searchFocused: Bool

    private static let previewDelayNanoseconds: UInt64 = 120_000_000

    private func applySearch(_ names: [String]) -> [String] {
        if searchText.isEmpty { return names }
        return names.filter { $0.localizedStandardContains(searchText) }
    }

    private var allItems: [String] {
        filteredFavorites + filteredDark + filteredLight
    }

    private var effectiveBackgroundOpacity: Double {
        store.hasWallpaper ? store.backgroundOpacity : 1.0
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

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasOnlyShiftModifier = modifiers == [.shift]

            switch event.keyCode {
            case 126 where modifiers.isEmpty: // Up arrow
                moveSelection(by: -1)
                return nil
            case 125 where modifiers.isEmpty: // Down arrow
                moveSelection(by: 1)
                return nil
            case 36 where modifiers.isEmpty: // Return
                guard allItems.indices.contains(selectedIndex) else { return nil }
                commitTheme(allItems[selectedIndex])
                return nil
            case 53 where modifiers.isEmpty: // Escape
                dismissPicker()
                return nil
            default:
                break
            }

            guard modifiers.isEmpty || hasOnlyShiftModifier else { return event }

            switch event.charactersIgnoringModifiers?.lowercased() {
            case "j":
                moveSelection(by: 1)
                return nil
            case "k":
                moveSelection(by: -1)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func metadata(for name: String) -> ThemePickerMetadata? {
        if let cached = metadataByName[name] {
            return cached
        }

        guard let parsed = themeManager.previewTheme(name: name) else {
            return nil
        }

        return Self.metadata(from: parsed)
    }

    private static func metadata(from parsed: TerminalTheme) -> ThemePickerMetadata {
        let isLight: Bool
        if let components = Color.hexComponents(parsed.background) {
            let luminance = 0.299 * components.red + 0.587 * components.green + 0.114 * components.blue
            isLight = luminance > 0.5
        } else {
            isLight = false
        }

        return ThemePickerMetadata(
            isLight: isLight,
            swatches: [
                parsed.background,
                parsed.foreground,
                parsed.palette[1],
                parsed.palette[2],
                parsed.palette[4],
                parsed.palette[5],
            ]
        )
    }

    private func refreshFilteredThemes() {
        let favoritesSet = Set(ThemeManager.favorites)
        let availableSet = Set(themeManager.availableThemes)

        filteredFavorites = applySearch(ThemeManager.favorites.filter { availableSet.contains($0) })

        let searched = searchText.isEmpty
            ? themeManager.availableThemes
            : themeManager.availableThemes.filter { $0.localizedStandardContains(searchText) }

        var nextDark: [String] = []
        var nextLight: [String] = []

        for name in searched where !favoritesSet.contains(name) {
            if metadata(for: name)?.isLight == true {
                nextLight.append(name)
            } else {
                nextDark.append(name)
            }
        }

        filteredDark = nextDark
        filteredLight = nextLight
    }

    private func warmThemeMetadata() {
        preloadTask?.cancel()
        let names = themeManager.availableThemes

        preloadTask = Task.detached(priority: .utility) {
            var loaded: [String: ThemePickerMetadata] = [:]
            loaded.reserveCapacity(names.count)

            for name in names {
                guard !Task.isCancelled,
                      let parsed = TerminalTheme.load(name: name) else {
                    continue
                }
                loaded[name] = Self.metadata(from: parsed)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                metadataByName.merge(loaded) { current, _ in current }
                for (name, metadata) in loaded {
                    if themeManager.parsedCache[name] == nil,
                       let parsed = TerminalTheme.load(name: name) {
                        themeManager.parsedCache[name] = parsed
                    }
                    metadataByName[name] = metadata
                }
                refreshFilteredThemes()
            }
        }
    }

    var body: some View {
        ZStack {
            BlinkModalBackdrop(
                onDismiss: dismissPicker,
                accessibilityLabel: "Dismiss"
            )

            BlinkModalPanel(width: 500) {
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
                .frame(height: 480)
            }
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
            refreshFilteredThemes()
            if let idx = allItems.firstIndex(of: store.theme) {
                selectedIndex = idx
            }
            requestSearchFocus()
            installKeyMonitor()
            warmThemeMetadata()
            previewSelectedTheme()
        }
        .onChange(of: store.themePickerFocusRequest) {
            requestSearchFocus()
        }
        .onChange(of: searchText) {
            selectedIndex = 0
            refreshFilteredThemes()
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
            removeKeyMonitor()
            previewTask?.cancel()
            preloadTask?.cancel()
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
            ThemePickerRow(
                name: name,
                isSelected: isSelected,
                isCurrent: isCurrent,
                metadata: metadata(for: name)
            )
        }
        .buttonStyle(.plain)
        .id(name)
        .contentShape(Rectangle())
        .pointerCursor()
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
        scheduleThemePreview(name)
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

    private func scheduleThemePreview(_ name: String) {
        previewTask?.cancel()
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.previewDelayNanoseconds)
            guard !Task.isCancelled,
                  let termTheme = themeManager.previewTheme(name: name) else {
                return
            }

            themeManager.setTheme(name: name)
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
        previewTask?.cancel()
        previewTask = nil
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

private struct ThemePickerRow: View {
    @Environment(\.theme) private var theme

    let name: String
    let isSelected: Bool
    let isCurrent: Bool
    let metadata: ThemePickerMetadata?

    @State private var isHovered = false

    var body: some View {
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

            if let metadata {
                HStack(spacing: 4) {
                    ForEach(Array(metadata.swatches.enumerated()), id: \.offset) { idx, swatch in
                        Circle()
                            .fill(Color(hex: swatch))
                            .frame(width: 10, height: 10)
                            .overlay {
                                if idx == 0 {
                                    Circle().stroke(theme.border, lineWidth: 0.5)
                                }
                            }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .blinkSelectableRow(isSelected: isSelected, isHovered: isHovered)
        .onHover { hovered in
            isHovered = hovered
        }
    }
}
