import SwiftUI
import AppKit

struct CommandPalette: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool

    private func requestSearchFocus() {
        searchFocused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            searchFocused = true
        }
    }

    private func moveSelection(by delta: Int) {
        guard !filteredCommands.isEmpty else { return }
        let count = filteredCommands.count
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
            case 48 where modifiers.isEmpty: // Tab
                moveSelection(by: 1)
                return nil
            case 48 where hasOnlyShiftModifier: // Shift-Tab
                moveSelection(by: -1)
                return nil
            case 36 where modifiers.isEmpty: // Return
                guard filteredCommands.indices.contains(selectedIndex) else { return nil }
                run(filteredCommands[selectedIndex])
                return nil
            case 53 where modifiers.isEmpty: // Escape
                onDismiss()
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

    private struct PaletteCommand: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let category: String
        let shortcut: String?
        let keywords: [String]
        let isEnabled: Bool
        let action: () -> Void
    }

    private var panelBackground: some ShapeStyle {
        if store.hasWallpaper {
            AnyShapeStyle(theme.bg.opacity(store.backgroundOpacity))
        } else {
            AnyShapeStyle(theme.bg.opacity(0.97))
        }
    }

    private var commands: [PaletteCommand] {
        let hasProject = store.activeProjectId != nil

        return [
            PaletteCommand(
                id: "switch-project",
                title: "Switch Project",
                subtitle: "Open the project switcher",
                category: "Workspace",
                shortcut: "Cmd-P",
                keywords: ["project", "workspace", "switch", "open"],
                isEnabled: !store.projects.isEmpty
            ) {
                store.presentProjectSwitcher(focusSearch: true)
            },
            PaletteCommand(
                id: "switch-theme",
                title: "Switch Theme",
                subtitle: "Open the theme picker",
                category: "Appearance",
                shortcut: "Cmd-Shift-T",
                keywords: ["theme", "appearance", "colors"],
                isEnabled: !themeManager.availableThemes.isEmpty
            ) {
                store.presentThemePicker(focusSearch: true)
            },
            PaletteCommand(
                id: "settings",
                title: store.activeView == .settings ? "Close Settings" : "Open Settings",
                subtitle: "Toggle the settings screen",
                category: "App",
                shortcut: "Cmd-,",
                keywords: ["settings", "preferences", "config"],
                isEnabled: true
            ) {
                store.toggleSettings()
            },
            PaletteCommand(
                id: "focus-sidebar",
                title: store.sidebarFocused ? "Focus Terminal" : "Focus Sidebar",
                subtitle: store.sidebarFocused ? "Return keyboard focus to the active terminal" : "Move keyboard focus into the sidebar",
                category: "Layout",
                shortcut: nil,
                keywords: ["sidebar", "panel", "focus", "terminal"],
                isEnabled: store.activeProjectId != nil || store.sidebarVisible
            ) {
                if store.sidebarFocused {
                    store.focusTerminal()
                } else {
                    store.focusSidebar()
                }
            },
            PaletteCommand(
                id: "overview",
                title: store.isOverviewMode ? "Close Overview" : "Open Overview",
                subtitle: "Toggle workspace overview mode",
                category: "Layout",
                shortcut: "Cmd-O",
                keywords: ["overview", "grid", "layout"],
                isEnabled: hasProject
            ) {
                store.toggleOverview()
            },
            PaletteCommand(
                id: "new-window",
                title: "New Window",
                subtitle: "Open a new terminal window in the active project",
                category: "Windows",
                shortcut: "Cmd-T",
                keywords: ["new", "window", "tab", "terminal"],
                isEnabled: hasProject
            ) {
                if let projectId = store.activeProjectId {
                    store.openTab(projectId: projectId)
                }
            },
            PaletteCommand(
                id: "split-below",
                title: "Split Below",
                subtitle: "Open a new terminal beneath the active pane",
                category: "Windows",
                shortcut: "Cmd-Shift-_",
                keywords: ["split", "below", "under", "pane", "terminal"],
                isEnabled: hasProject
            ) {
                store.splitActivePaneWithNewTab()
            },
            PaletteCommand(
                id: "split-right",
                title: "Split Right",
                subtitle: "Open a new terminal to the right of the active column",
                category: "Windows",
                shortcut: "Cmd-Shift-|",
                keywords: ["split", "right", "column", "pane", "terminal"],
                isEnabled: hasProject
            ) {
                store.splitActiveColumnWithNewTab()
            },
            PaletteCommand(
                id: "close-window",
                title: "Close Window",
                subtitle: "Close the active window",
                category: "Windows",
                shortcut: "Cmd-W",
                keywords: ["close", "window", "tab"],
                isEnabled: store.activeTabId != nil
            ) {
                store.closeActiveTab()
            },
            PaletteCommand(
                id: "open-git",
                title: "Open Git",
                subtitle: "Open lazygit for the active project",
                category: "Tools",
                shortcut: "Cmd-G",
                keywords: ["git", "lazygit", "source control"],
                isEnabled: hasProject
            ) {
                store.openOrFocusCommandTabForActiveProject(command: "lazygit", label: "lazygit")
            },
            PaletteCommand(
                id: "open-files",
                title: "Open Files",
                subtitle: "Open Yazi for the active project",
                category: "Tools",
                shortcut: "Cmd-Shift-F",
                keywords: ["files", "yazi", "browser", "finder"],
                isEnabled: hasProject
            ) {
                let command = YaziLauncher.command(theme: themeManager.activeTerminalTheme)
                store.openOrFocusCommandTabForActiveProject(command: command, label: "Yazi")
            },
            PaletteCommand(
                id: "open-neovim",
                title: "Open Neovim",
                subtitle: "Open Neovim for the active project",
                category: "Tools",
                shortcut: "Cmd-Shift-N",
                keywords: ["neovim", "nvim", "vim", "editor"],
                isEnabled: hasProject
            ) {
                let command = NvimLauncher.command()
                store.openOrFocusCommandTabForActiveProject(command: command, label: "Neovim")
            },
            PaletteCommand(
                id: "open-spotify",
                title: "Open Spotify",
                subtitle: "Open Spotatui in a maximized window",
                category: "Tools",
                shortcut: "Cmd-Shift-S",
                keywords: ["spotify", "spotatui", "music", "player"],
                isEnabled: hasProject
            ) {
                let command = themeManager.activeTerminalTheme?.spotatuiLaunchCommand() ?? "spotatui"
                store.openOrFocusCommandTabForActiveProject(command: command, label: "Spotify", maximizeColumn: true)
            },
            PaletteCommand(
                id: "focus-left",
                title: "Focus Left",
                subtitle: "Move focus to the window on the left",
                category: "Navigation",
                shortcut: "Cmd-H / Cmd-←",
                keywords: ["focus", "left", "window", "pane"],
                isEnabled: hasProject
            ) {
                store.focusLeft()
            },
            PaletteCommand(
                id: "focus-right",
                title: "Focus Right",
                subtitle: "Move focus to the window on the right",
                category: "Navigation",
                shortcut: "Cmd-L / Cmd-→",
                keywords: ["focus", "right", "window", "pane"],
                isEnabled: hasProject
            ) {
                store.focusRight()
            },
            PaletteCommand(
                id: "focus-down",
                title: "Focus Down",
                subtitle: "Move focus to the window below",
                category: "Navigation",
                shortcut: "Cmd-J",
                keywords: ["focus", "down", "window", "pane"],
                isEnabled: hasProject
            ) {
                store.focusDown()
            },
            PaletteCommand(
                id: "focus-up",
                title: "Focus Up",
                subtitle: "Move focus to the window above",
                category: "Navigation",
                shortcut: "Cmd-K",
                keywords: ["focus", "up", "window", "pane"],
                isEnabled: hasProject
            ) {
                store.focusUp()
            },
            PaletteCommand(
                id: "move-left",
                title: "Move Window Left",
                subtitle: "Move the current window one column left",
                category: "Layout",
                shortcut: "Cmd-Shift-H",
                keywords: ["move", "left", "window", "column"],
                isEnabled: hasProject
            ) {
                store.moveColumnLeft()
            },
            PaletteCommand(
                id: "move-right",
                title: "Move Window Right",
                subtitle: "Move the current window one column right",
                category: "Layout",
                shortcut: "Cmd-Shift-L",
                keywords: ["move", "right", "window", "column"],
                isEnabled: hasProject
            ) {
                store.moveColumnRight()
            },
            PaletteCommand(
                id: "absorb-left",
                title: "Absorb from Left",
                subtitle: "Pull a tab in from the left column",
                category: "Layout",
                shortcut: "Cmd-Shift-J",
                keywords: ["absorb", "left", "merge", "window"],
                isEnabled: hasProject
            ) {
                store.absorbFromLeft()
            },
            PaletteCommand(
                id: "absorb-right",
                title: "Absorb from Right",
                subtitle: "Pull a tab in from the right column",
                category: "Layout",
                shortcut: "Cmd-Shift-K",
                keywords: ["absorb", "right", "merge", "window"],
                isEnabled: hasProject
            ) {
                store.absorbFromRight()
            },
            PaletteCommand(
                id: "expel-pane",
                title: "Expel Pane",
                subtitle: "Break the active tab into its own column",
                category: "Layout",
                shortcut: "Cmd-Shift-E",
                keywords: ["expel", "split", "column", "window"],
                isEnabled: hasProject
            ) {
                store.expelActiveTab()
            },
        ]
    }

    private var filteredCommands: [PaletteCommand] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return commands }

        return commands.filter { command in
            command.title.localizedStandardContains(needle)
            || command.subtitle.localizedStandardContains(needle)
            || command.category.localizedStandardContains(needle)
            || command.keywords.contains(where: { $0.localizedStandardContains(needle) })
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Dismiss command palette")

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "command")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)

                    TextField("Run a command...", text: $searchText)
                        .font(Fonts.primary(size: 14))
                        .textFieldStyle(.plain)
                        .foregroundStyle(theme.text)
                        .focused($searchFocused)

                    Spacer(minLength: 8)

                    Text("Command Palette")
                        .font(Fonts.primary(size: 11, weight: .medium))
                        .foregroundStyle(theme.textDim)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                theme.border.frame(height: 1)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if filteredCommands.isEmpty {
                                Text("No matching commands")
                                    .font(Fonts.primary(size: 13))
                                    .foregroundStyle(theme.textDim)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 28)
                            } else {
                                ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                                    commandRow(command, isSelected: index == selectedIndex)
                                        .id(command.id)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 360)
                    .onAppear {
                        scrollSelection(in: proxy, animated: false)
                    }
                    .onChange(of: selectedIndex) {
                        scrollSelection(in: proxy, animated: false)
                    }
                    .onChange(of: filteredCommands.map(\.id)) {
                        scrollSelection(in: proxy, animated: false)
                    }
                }

                theme.border.frame(height: 1)

                HStack(spacing: 14) {
                    hint("↑↓ / tab", label: "cycle")
                    hint("↵", label: "run")
                    hint("esc", label: "close")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 560)
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
                guard !filteredCommands.isEmpty else { return .ignored }

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
                guard filteredCommands.indices.contains(selectedIndex) else { return .ignored }
                run(filteredCommands[selectedIndex])
                return .handled
            }
            .onKeyPress(.escape) {
                onDismiss()
                return .handled
            }
        }
        .onAppear {
            selectedIndex = 0
            requestSearchFocus()
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: searchText) {
            selectedIndex = 0
        }
        .onChange(of: filteredCommands.count) {
            if filteredCommands.isEmpty {
                selectedIndex = 0
            } else {
                selectedIndex = min(selectedIndex, filteredCommands.count - 1)
            }
        }
    }

    private func commandRow(_ command: PaletteCommand, isSelected: Bool) -> some View {
        return AnyView(defaultCommandRow(command, isSelected: isSelected))
    }

    private func defaultCommandRow(_ command: PaletteCommand, isSelected: Bool) -> some View {
        Button {
            run(command)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(command.title)
                            .font(Fonts.primary(size: 13, weight: .bold))
                            .foregroundStyle(command.isEnabled ? theme.text : theme.textDim)

                        Text(command.category.uppercased())
                            .font(Fonts.primary(size: 10))
                            .foregroundStyle(theme.accent)
                    }

                    Text(command.subtitle)
                        .font(Fonts.primary(size: 11))
                        .foregroundStyle(command.isEnabled ? theme.textDim : theme.textDim.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(Fonts.primary(size: 10))
                        .foregroundStyle(theme.textMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? theme.accent.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
            .opacity(command.isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!command.isEnabled)
    }

    private func run(_ command: PaletteCommand) {
        guard command.isEnabled else { return }
        searchFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
        onDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            command.action()
        }
    }

    private func scrollSelection(in proxy: ScrollViewProxy, animated: Bool = true) {
        guard filteredCommands.indices.contains(selectedIndex) else { return }
        let commandId = filteredCommands[selectedIndex].id
        if animated {
            withAnimation(.snappy(duration: 0.18)) {
                proxy.scrollTo(commandId, anchor: .center)
            }
        } else {
            proxy.scrollTo(commandId, anchor: .center)
        }
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
