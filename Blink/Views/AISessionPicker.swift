import AppKit
import SwiftUI

struct AISessionPicker: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let onDismiss: () -> Void

    @State private var selectedIndex = 0
    @State private var keyMonitor: Any?
    @State private var hoveredOptionId: String?

    private struct Option: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let systemImage: String
        let action: () -> Void
    }

    private var destinationLabel: String {
        if let activeWorkspace = store.workspaces.first(where: { $0.id == store.activeWorkspaceId }) {
            return activeWorkspace.name
        }
        return "Scratch Space"
    }

    private var options: [Option] {
        [
            Option(
                id: "claude",
                title: "Claude Code",
                subtitle: "Launch in \(destinationLabel)",
                systemImage: "sparkles.rectangle.stack",
                action: { _ = store.openClaudeSession() }
            ),
            Option(
                id: "codex",
                title: "Codex",
                subtitle: "Launch in \(destinationLabel)",
                systemImage: "cpu",
                action: { _ = store.openCodexSession() }
            ),
            Option(
                id: "opencode",
                title: "OpenCode",
                subtitle: "Launch in \(destinationLabel)",
                systemImage: "chevron.left.forwardslash.chevron.right",
                action: { _ = store.openOpenCodeSession() }
            ),
        ]
    }

    private var panelBackground: some ShapeStyle {
        if store.hasWallpaper {
            AnyShapeStyle(theme.bg.opacity(store.backgroundOpacity))
        } else {
            AnyShapeStyle(theme.bg.opacity(0.97))
        }
    }

    private func moveSelection(by delta: Int) {
        guard !options.isEmpty else { return }
        let count = options.count
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])

            switch event.keyCode {
            case 126 where modifiers.isEmpty: // Up arrow
                moveSelection(by: -1)
                return nil
            case 125 where modifiers.isEmpty: // Down arrow
                moveSelection(by: 1)
                return nil
            case 36 where modifiers.isEmpty: // Return
                guard options.indices.contains(selectedIndex) else { return nil }
                select(options[selectedIndex])
                return nil
            case 53 where modifiers.isEmpty: // Escape
                onDismiss()
                return nil
            default:
                break
            }

            guard modifiers.isEmpty else { return event }

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

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Dismiss AI session picker")

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Open AI Session")
                        .font(Fonts.primary(size: 16, weight: .bold))
                        .foregroundStyle(theme.text)

                    Text("Choose an AI CLI session to open.")
                        .font(Fonts.primary(size: 12))
                        .foregroundStyle(theme.textDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                theme.border.frame(height: 1)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        optionRow(option, isSelected: index == selectedIndex)
                    }
                }
                .padding(.vertical, 6)

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
            .frame(width: 420)
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
                guard !options.isEmpty else { return .ignored }

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
                guard options.indices.contains(selectedIndex) else { return .ignored }
                select(options[selectedIndex])
                return .handled
            }
            .onKeyPress(.escape) {
                onDismiss()
                return .handled
            }
        }
        .onAppear {
            selectedIndex = 0
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
    }

    private func optionRow(_ option: Option, isSelected: Bool) -> some View {
        Button {
            select(option)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(Fonts.primary(size: 13, weight: .bold))
                        .foregroundStyle(isSelected ? theme.text : theme.textMuted)

                    Text(option.subtitle)
                        .font(Fonts.primary(size: 11))
                        .foregroundStyle(theme.textDim)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(rowBackground(isSelected: isSelected, isHovered: hoveredOptionId == option.id))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered in
            hoveredOptionId = isHovered ? option.id : nil
        }
        .pointerCursor()
    }

    private func rowBackground(isSelected: Bool, isHovered: Bool) -> some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(theme.accent.opacity(0.12))
        }

        if isHovered {
            return AnyShapeStyle(theme.accent.opacity(0.08))
        }

        return AnyShapeStyle(Color.clear)
    }

    private func select(_ option: Option) {
        option.action()
        onDismiss()
    }

    private func hint(_ keys: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(Fonts.primary(size: 11, weight: .medium))
                .foregroundStyle(theme.text)
            Text(label)
                .font(Fonts.primary(size: 11))
                .foregroundStyle(theme.textDim)
        }
    }
}
