import SwiftUI

struct AISettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("AI")
                    .font(Fonts.primary(size: 18, weight: .bold, family: store.uiFontFamily))
                    .foregroundStyle(theme.text)

                apiKeySection
                modelSection
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
}
