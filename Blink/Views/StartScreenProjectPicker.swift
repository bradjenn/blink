import SwiftUI

struct StartScreenProjectPicker: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let onDismiss: () -> Void
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    private func requestSearchFocus() {
        searchFocused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            searchFocused = true
        }
    }

    private var panelBackground: some ShapeStyle {
        if store.hasWallpaper {
            AnyShapeStyle(theme.bg.opacity(store.backgroundOpacity))
        } else {
            AnyShapeStyle(theme.bg.opacity(0.97))
        }
    }

    private func moveSelection(by delta: Int) {
        guard !filteredProjects.isEmpty else { return }
        let count = filteredProjects.count
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private var filteredProjects: [Project] {
        store.projects.filter { project in
            searchText.isEmpty
                || project.name.localizedStandardContains(searchText)
                || project.path.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Dismiss project picker")

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(">")
                        .font(Fonts.primary(size: 14))
                        .foregroundStyle(theme.accent)

                    TextField("Switch project...", text: $searchText)
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
                            if filteredProjects.isEmpty {
                                Text("No matching projects")
                                    .font(Fonts.primary(size: 13))
                                    .foregroundStyle(theme.textDim)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 28)
                            } else {
                                ForEach(Array(filteredProjects.enumerated()), id: \.element.id) { index, project in
                                    projectRow(project, isSelected: index == selectedIndex)
                                        .id(project.id)
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
                    .onChange(of: filteredProjects.map(\.id)) {
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
            .frame(width: 500)
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
                guard !filteredProjects.isEmpty else { return .ignored }

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
                guard filteredProjects.indices.contains(selectedIndex) else { return .ignored }
                selectProject(filteredProjects[selectedIndex].id)
                return .handled
            }
        }
        .onAppear {
            if let preferredProjectId = store.activeProjectId ?? store.lastSelectedProjectId,
               let index = filteredProjects.firstIndex(where: { $0.id == preferredProjectId }) {
                selectedIndex = index
            }
            requestSearchFocus()
        }
        .onChange(of: store.projectSwitcherFocusRequest) {
            requestSearchFocus()
        }
        .onChange(of: searchText) {
            selectedIndex = 0
        }
        .onChange(of: filteredProjects.count) {
            if filteredProjects.isEmpty {
                selectedIndex = 0
            } else {
                selectedIndex = min(selectedIndex, filteredProjects.count - 1)
            }
        }
    }

    private func projectRow(_ project: Project, isSelected: Bool) -> some View {
        Button {
            selectProject(project.id)
        } label: {
            HStack(spacing: 12) {
                ProjectFavicon(projectName: project.name, projectPath: project.path, size: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(Fonts.primary(size: 13, weight: .bold))
                        .foregroundStyle(isSelected ? theme.text : theme.textMuted)
                        .lineLimit(1)

                    Text(project.displayPath)
                        .font(Fonts.primary(size: 11))
                        .foregroundStyle(theme.textDim)
                        .lineLimit(1)
                }

                Spacer()

                if store.activeProjectId == project.id {
                    Text("current")
                        .font(Fonts.primary(size: 10))
                        .foregroundStyle(theme.accent)
                } else if store.lastSelectedProjectId == project.id {
                    Text("last")
                        .font(Fonts.primary(size: 10))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? theme.accent.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func selectProject(_ id: String) {
        onSelect(id)
        onDismiss()
    }

    private func scrollSelection(in proxy: ScrollViewProxy, animated: Bool = true) {
        guard filteredProjects.indices.contains(selectedIndex) else { return }
        let projectId = filteredProjects[selectedIndex].id

        DispatchQueue.main.async {
            if animated {
                withAnimation(.snappy(duration: 0.18)) {
                    proxy.scrollTo(projectId, anchor: .center)
                }
            } else {
                proxy.scrollTo(projectId, anchor: .center)
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
