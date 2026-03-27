import SwiftUI

struct AISettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @State private var codexStatus: CLIAvailabilityStatus?
    @State private var claudeStatus: CLIAvailabilityStatus?
    @State private var refreshingCLIStatus = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("AI")
                    .font(Fonts.primary(size: 18, weight: .bold, family: store.uiFontFamily))
                    .foregroundStyle(theme.text)

                apiKeySection
                modelSection
                fileLinksSection
                notesSection

                Spacer()
            }
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .task {
            await refreshCLIStatuses()
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local AI CLIs")
                .font(Fonts.primary(size: 14, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(theme.text)
            Text("Native project chat can run through the local `codex` or `claude` CLI. Make sure the provider you want to use is installed, available on your PATH, and already authenticated.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)
            Text("Planning Session uses both local CLIs together, so Blink can compare plans, show multiple routes, and hand work off into implementation.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)
            Text("By default, Planning Session starts with independent answers from both agents so neither one anchors the other unless you choose a lead.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)
            Text("Each thread stores provider session ids locally so later messages resume the same agent context for each CLI.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            cliStatusSection
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            @Bindable var store = store

            Text("Default Codex model")
                .font(Fonts.primary(size: 14, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(theme.text)
            Text("Optional default for Codex chats and the Codex side of Planning Session. Leave this blank to use the Codex CLI's configured default model.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)

            StyledTextField(text: $store.chatModel, placeholder: "Use Codex default")
                .frame(maxWidth: 300)

            Text("Default Claude model")
                .font(Fonts.primary(size: 14, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(theme.text)
            Text("Optional default for Claude chats and the Claude side of Planning Session. Leave this blank to use the Claude CLI's configured default model.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)

            StyledTextField(text: $store.claudeChatModel, placeholder: "Use Claude default")
                .frame(maxWidth: 300)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What Blink sends")
                .font(Fonts.primary(size: 14, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(theme.text)
            Text("Blink opens the selected CLI in the project root for each chat thread, then resumes the saved provider session on later turns. Message history and provider session ids are stored locally so project chats and Planning Session threads can continue across app relaunches.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fileLinksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            @Bindable var store = store

            Text("Open file links with")
                .font(Fonts.primary(size: 14, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(theme.text)
            Text("Choose where chat file links and future code actions open. Blink Neovim stays inside Blink and reuses the tmux-backed editor pane when possible.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Cursor, Zed, and VS Code use their shell CLI, so make sure `cursor`, `zed`, or `code` is available on your PATH.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            StyledDropdown(
                selection: store.fileEditorLauncher,
                options: FileEditorLauncher.allCases,
                label: { $0.displayName },
                onChange: { store.fileEditorLauncher = $0 }
            )
            .frame(maxWidth: 300)

            if store.fileEditorLauncher == .custom {
                Text("Use `{path}`, `{line}`, and `{column}` in the command template. Example: `code --goto {path}:{line}:{column}`")
                    .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                StyledTextField(
                    text: $store.fileEditorCustomCommand,
                    placeholder: "open {path}"
                )
                .frame(maxWidth: 520)
            }
        }
    }

    private var cliStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("CLI status")
                    .font(Fonts.primary(size: 14, weight: .medium, family: store.uiFontFamily))
                    .foregroundStyle(theme.text)

                Spacer()

                Button(refreshingCLIStatus ? "Checking..." : "Refresh") {
                    Task {
                        await refreshCLIStatuses(forceRefresh: true)
                    }
                }
                .disabled(refreshingCLIStatus)
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(refreshingCLIStatus ? theme.textDim : theme.accent)
                .buttonStyle(.plain)
                .pointerCursor()
            }

            if let codexStatus {
                cliStatusCard(
                    title: "Codex",
                    status: codexStatus,
                    installHint: "Install Codex and make sure `codex` resolves from your login shell."
                )
            }

            if let claudeStatus {
                cliStatusCard(
                    title: "Claude Code",
                    status: claudeStatus,
                    installHint: "Install Claude Code and make sure `claude` resolves from your login shell."
                )
            }
        }
        .padding(.top, 8)
    }

    private func cliStatusCard(title: String, status: CLIAvailabilityStatus, installHint: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(status.isAvailable ? theme.green : theme.danger)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(Fonts.primary(size: 12, weight: .medium, family: store.uiFontFamily))
                    .foregroundStyle(theme.text)

                Text(status.isAvailable ? "Available" : "Not found")
                    .font(Fonts.primary(size: 11, family: store.uiFontFamily))
                    .foregroundStyle(status.isAvailable ? theme.green : theme.danger)
            }

            if let executableURL = status.executableURL {
                Text(executableURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.textMuted)
                    .textSelection(.enabled)
            } else {
                Text(installHint)
                    .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.border.opacity(0.9), lineWidth: 1)
        )
    }

    private func refreshCLIStatuses(forceRefresh: Bool = false) async {
        if refreshingCLIStatus {
            return
        }

        refreshingCLIStatus = true
        defer { refreshingCLIStatus = false }

        if forceRefresh {
            await LocalCLIResolver.shared.refresh()
        }

        async let resolvedCodexStatus = LocalCLIResolver.shared.status(for: "codex")
        async let resolvedClaudeStatus = LocalCLIResolver.shared.status(for: "claude")

        codexStatus = await resolvedCodexStatus
        claudeStatus = await resolvedClaudeStatus
    }
}
