import SwiftUI

struct StartScreenWorkspacePicker: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let onDismiss: () -> Void
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var hoveredWorkspaceId: String?
    @FocusState private var searchFocused: Bool

    private func requestSearchFocus() {
        searchFocused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            searchFocused = true
        }
    }

    private func moveSelection(by delta: Int) {
        guard !filteredWorkspaces.isEmpty else { return }
        let count = filteredWorkspaces.count
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private var filteredWorkspaces: [Workspace] {
        store.workspaces.filter { workspace in
            searchText.isEmpty
                || workspace.name.localizedStandardContains(searchText)
                || workspace.path.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            BlinkModalBackdrop(
                onDismiss: onDismiss,
                accessibilityLabel: "Dismiss workspace picker"
            )

            BlinkModalPanel(width: 500) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text(">")
                            .font(Fonts.primary(size: 14))
                            .foregroundStyle(theme.accent)

                        TextField("Switch workspace...", text: $searchText)
                            .font(Fonts.primary(size: 14))
                            .textFieldStyle(.plain)
                            .foregroundStyle(theme.text)
                            .focused($searchFocused)
                            .onSubmit {
                                selectCurrentWorkspace()
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    theme.border.frame(height: 1)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                if filteredWorkspaces.isEmpty {
                                    Text("No matching workspaces")
                                        .font(Fonts.primary(size: 13))
                                        .foregroundStyle(theme.textDim)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 28)
                                } else {
                                    ForEach(Array(filteredWorkspaces.enumerated()), id: \.element.id) { index, workspace in
                                        workspaceRow(workspace, isSelected: index == selectedIndex)
                                            .id(workspace.id)
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
                        .onChange(of: filteredWorkspaces.map(\.id)) {
                            scrollSelection(in: proxy, animated: false)
                        }
                    }
                    .frame(maxHeight: 320)

                    theme.border.frame(height: 1)

                    HStack(spacing: 14) {
                        hint("↑↓ j/k", label: "navigate")
                        hint("\u{21B5}", label: "select")
                        hint("esc", label: "close")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                guard !filteredWorkspaces.isEmpty else { return .ignored }

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
            .onKeyPress(.escape) {
                onDismiss()
                return .handled
            }
            .onKeyPress(.return) {
                guard selectCurrentWorkspace() else { return .ignored }
                return .handled
            }
        }
        .onAppear {
            if let preferredWorkspaceId = store.activeWorkspaceId ?? store.lastSelectedWorkspaceId,
               let index = filteredWorkspaces.firstIndex(where: { $0.id == preferredWorkspaceId }) {
                selectedIndex = index
            }
            requestSearchFocus()
        }
        .onChange(of: store.workspaceSwitcherFocusRequest) {
            requestSearchFocus()
        }
        .onChange(of: searchText) {
            selectedIndex = 0
        }
        .onChange(of: filteredWorkspaces.count) {
            if filteredWorkspaces.isEmpty {
                selectedIndex = 0
            } else {
                selectedIndex = min(selectedIndex, filteredWorkspaces.count - 1)
            }
        }
    }

    private func workspaceRow(_ workspace: Workspace, isSelected: Bool) -> some View {
        let isPathMissing = store.isWorkspacePathMissing(workspace.id)
        return Button {
            selectWorkspace(workspace.id)
        } label: {
            HStack(spacing: 12) {
                WorkspaceFavicon(workspaceName: workspace.name, workspacePath: workspace.path, size: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .font(Fonts.primary(size: 13, weight: .bold))
                        .foregroundStyle(isSelected ? theme.text : theme.textMuted)
                        .lineLimit(1)

                    Text(subtitle(for: workspace, isPathMissing: isPathMissing))
                        .font(Fonts.primary(size: 11))
                        .foregroundStyle(isPathMissing ? theme.yellow : theme.textDim)
                        .lineLimit(1)
                }

                Spacer()

                if store.activeWorkspaceId == workspace.id {
                    Text("current")
                        .font(Fonts.primary(size: 10))
                        .foregroundStyle(theme.accent)
                } else if store.lastSelectedWorkspaceId == workspace.id {
                    Text("last")
                        .font(Fonts.primary(size: 10))
                        .foregroundStyle(theme.accent)
                } else if workspace.isScratchSpace {
                    Text("scratch")
                        .font(Fonts.primary(size: 10))
                        .foregroundStyle(theme.textDim)
                } else if isPathMissing {
                    Text("missing")
                        .font(Fonts.primary(size: 10))
                        .foregroundStyle(theme.yellow)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .blinkSelectableRow(isSelected: isSelected, isHovered: hoveredWorkspaceId == workspace.id)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered in
            hoveredWorkspaceId = isHovered ? workspace.id : nil
        }
        .pointerCursor()
    }

    private func subtitle(for workspace: Workspace, isPathMissing: Bool) -> String {
        if workspace.isScratchSpace {
            return "Shells, AI sessions, and browser panes"
        }

        if isPathMissing {
            return "Workspace folder is missing"
        }

        return workspace.displayPath
    }

    private func selectWorkspace(_ id: String) {
        onSelect(id)
        onDismiss()
    }

    @discardableResult
    private func selectCurrentWorkspace() -> Bool {
        guard filteredWorkspaces.indices.contains(selectedIndex) else { return false }
        selectWorkspace(filteredWorkspaces[selectedIndex].id)
        return true
    }

    private func scrollSelection(in proxy: ScrollViewProxy, animated: Bool = true) {
        guard filteredWorkspaces.indices.contains(selectedIndex) else { return }
        let workspaceId = filteredWorkspaces[selectedIndex].id

        DispatchQueue.main.async {
            if animated {
                withAnimation(.snappy(duration: 0.18)) {
                    proxy.scrollTo(workspaceId, anchor: .center)
                }
            } else {
                proxy.scrollTo(workspaceId, anchor: .center)
            }
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
