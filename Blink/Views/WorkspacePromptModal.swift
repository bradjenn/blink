import AppKit
import SwiftUI

struct WorkspacePromptModal: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let prompt: WorkspacePromptState
    let onDismiss: () -> Void

    @State private var value = ""
    @State private var errorMessage: String?
    @State private var keyMonitor: Any?
    @FocusState private var fieldFocused: Bool

    private var workspace: Workspace? {
        store.workspaces.first(where: { $0.id == prompt.workspaceId })
    }

    private var title: String {
        switch prompt.kind {
        case .rename:
            return "Rename Workspace"
        case .relink:
            return "Relink Workspace"
        }
    }

    private var message: String {
        let name = workspace?.name ?? "this workspace"

        switch prompt.kind {
        case .rename:
            return "Choose a new name for \(name)."
        case .relink:
            return "Point \(name) at the folder Blink should use."
        }
    }

    private var submitTitle: String {
        switch prompt.kind {
        case .rename:
            return "Rename Workspace"
        case .relink:
            return "Relink Workspace"
        }
    }

    private var fieldLabel: String {
        switch prompt.kind {
        case .rename:
            return "Workspace Name"
        case .relink:
            return "Folder Path"
        }
    }

    private var helpText: String {
        switch prompt.kind {
        case .rename:
            return "This updates the workspace label in Blink only."
        case .relink:
            return "Choose an existing folder or browse for one."
        }
    }

    private var canSubmit: Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            BlinkModalBackdrop(
                onDismiss: onDismiss,
                accessibilityLabel: "Dismiss workspace prompt"
            )

            BlinkModalPanel(width: 520, cornerRadius: 16) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(Fonts.primary(size: 18, weight: .bold))
                            .foregroundStyle(theme.text)

                        Text(message)
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.textDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                    theme.border.frame(height: 1)

                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(fieldLabel)
                                .font(Fonts.primary(size: 11, weight: .bold))
                                .foregroundStyle(theme.textMuted)
                                .textCase(.uppercase)

                            HStack(spacing: 10) {
                                TextField("", text: $value)
                                    .textFieldStyle(.plain)
                                    .font(Fonts.primary(size: 14, weight: .medium))
                                    .foregroundStyle(theme.text)
                                    .focused($fieldFocused)
                                    .onSubmit { submit() }

                                if prompt.kind == .relink {
                                    Button("Browse") {
                                        if let path = store.chooseExistingWorkspaceFolder(startingAt: value) {
                                            value = path
                                            errorMessage = nil
                                        }
                                    }
                                    .buttonStyle(BlinkActionButtonStyle(kind: .secondaryCompact))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(theme.border.opacity(0.18))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(theme.border, lineWidth: 1)
                            )

                            Text(helpText)
                                .font(Fonts.primary(size: 11))
                                .foregroundStyle(theme.textDim)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(Fonts.primary(size: 12))
                                .foregroundStyle(theme.accent2)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(theme.accent2.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(20)

                    theme.border.frame(height: 1)

                    HStack(spacing: 10) {
                        Button("Cancel") {
                            onDismiss()
                        }
                        .buttonStyle(BlinkActionButtonStyle(kind: .secondary))

                        Spacer()

                        Button(submitTitle) {
                            submit()
                        }
                        .buttonStyle(BlinkActionButtonStyle(kind: .primary))
                        .disabled(!canSubmit)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }
        }
        .onAppear {
            value = prompt.initialValue
            installKeyMonitor()
            DispatchQueue.main.async {
                fieldFocused = true
            }
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            switch event.keyCode {
            case 36 where modifiers.isEmpty:
                submit()
                return nil
            case 53 where modifiers.isEmpty:
                onDismiss()
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

    private func submit() {
        guard canSubmit else { return }

        let didSucceed: Bool
        switch prompt.kind {
        case .rename:
            didSucceed = store.renameWorkspace(prompt.workspaceId, to: value)
            if !didSucceed {
                errorMessage = "Enter a workspace name to continue."
            }
        case .relink:
            didSucceed = store.relinkWorkspace(prompt.workspaceId, toPath: value)
            if !didSucceed {
                errorMessage = "Choose an existing folder to relink this workspace."
            }
        }

        guard didSucceed else { return }
        onDismiss()
    }
}
