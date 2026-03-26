import SwiftUI

struct ChatProviderModelMenu: View {
    @Environment(\.theme) private var theme

    let selectedProvider: ChatProvider
    let selectedModel: (ChatProvider) -> String
    let modelOptions: (ChatProvider) -> [(label: String, value: String)]
    let onSelect: (ChatProvider, String) -> Void

    @State private var focusedProvider: ChatProvider
    @State private var hoveredProvider: ChatProvider?
    @State private var hoveredModelValue: String?

    private let availableProviders: [ChatProvider] = [.codex, .claude]

    private var referenceModelProvider: ChatProvider {
        availableProviders.max { modelOptions($0).count < modelOptions($1).count } ?? .codex
    }

    init(
        selectedProvider: ChatProvider,
        selectedModel: @escaping (ChatProvider) -> String,
        modelOptions: @escaping (ChatProvider) -> [(label: String, value: String)],
        onSelect: @escaping (ChatProvider, String) -> Void
    ) {
        self.selectedProvider = selectedProvider == .secondOpinion ? .codex : selectedProvider
        self.selectedModel = selectedModel
        self.modelOptions = modelOptions
        self.onSelect = onSelect
        _focusedProvider = State(initialValue: selectedProvider == .secondOpinion ? .codex : selectedProvider)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(availableProviders.enumerated()), id: \.element) { index, provider in
                    Button(action: { focusedProvider = provider }) {
                        HStack(spacing: 10) {
                            Image(systemName: selectedProvider == provider ? "checkmark" : "")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.text)
                                .frame(width: 12)

                            providerIcon(provider)
                                .frame(width: 14, height: 14)

                            Text(provider.displayName)
                                .font(Fonts.primary(size: 13))
                                .foregroundStyle(providerForegroundStyle(for: provider))
                                .lineLimit(1)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(theme.textMuted.opacity(0.75))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(providerRowBackground(for: provider))
                    .onHover { isHovered in
                        if isHovered {
                            hoveredProvider = provider
                            focusedProvider = provider
                        } else if hoveredProvider == provider {
                            hoveredProvider = nil
                        }
                    }
                    .pointerCursor()

                    if index < availableProviders.count - 1 {
                        Divider()
                            .overlay(theme.border)
                    }
                }
            }
            .frame(width: 188)
            .background(theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )

            // Keep the submenu height fixed to the tallest provider list.
            modelList(for: referenceModelProvider)
                .hidden()
                .overlay(alignment: .topLeading) {
                    modelList(for: focusedProvider)
                        .id(focusedProvider)
                        .transition(.opacity)
                }
            .frame(width: 228)
            .background(theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
            .padding(.leading, -1)
        }
        .animation(.easeInOut(duration: 0.12), value: focusedProvider)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func providerIcon(_ provider: ChatProvider) -> some View {
        switch provider {
        case .codex:
            BundledSVGIcon(name: "codex-icon")
        case .claude:
            ClaudeIcon()
        case .secondOpinion:
            Image(systemName: "person.2.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(providerForegroundStyle(for: provider))
        }
    }

    private func providerForegroundStyle(for provider: ChatProvider) -> Color {
        if selectedProvider == provider || hoveredProvider == provider || focusedProvider == provider {
            return theme.text
        }

        return theme.textMuted
    }

    private func providerRowBackground(for provider: ChatProvider) -> Color {
        focusedProvider == provider ? theme.accent.opacity(0.08) : .clear
    }

    private func isSelectedModel(_ value: String) -> Bool {
        selectedProvider == focusedProvider && selectedModel(focusedProvider) == value
    }

    private func modelList(for provider: ChatProvider) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(modelOptions(provider).enumerated()), id: \.offset) { index, option in
                Button(action: { onSelect(provider, option.value) }) {
                    HStack(spacing: 10) {
                        Image(systemName: selectedProvider == provider && selectedModel(provider) == option.value ? "checkmark" : "")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .frame(width: 12)

                        Text(option.label)
                            .font(Fonts.primary(size: 13))
                            .foregroundStyle(modelForegroundStyle(for: provider, value: option.value))
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(modelRowBackground(for: provider, value: option.value))
                .onHover { isHovered in
                    hoveredModelValue = isHovered && focusedProvider == provider ? option.value : nil
                }
                .pointerCursor()

                if index < modelOptions(provider).count - 1 {
                    Divider()
                        .overlay(theme.border)
                }
            }
        }
    }

    private func modelForegroundStyle(for provider: ChatProvider, value: String) -> Color {
        if selectedProvider == provider && selectedModel(provider) == value || hoveredModelValue == value {
            return theme.text
        }

        return theme.textMuted
    }

    private func modelRowBackground(for provider: ChatProvider, value: String) -> Color {
        focusedProvider == provider && hoveredModelValue == value ? theme.accent.opacity(0.08) : .clear
    }
}

struct ChatModeMenu: View {
    @Environment(\.theme) private var theme

    let isPlanning: Bool
    let onSelect: (Bool) -> Void

    @State private var hoveredMode: Bool?

    var body: some View {
        VStack(spacing: 0) {
            modeRow(title: "Chat", icon: "bubble.left.fill", isPlanningMode: false)

            Divider()
                .overlay(theme.border)

            modeRow(title: "Planning", icon: "person.2.fill", isPlanningMode: true)
        }
        .frame(width: 180)
        .background(theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        .padding(.top, 4)
    }

    private func modeRow(title: String, icon: String, isPlanningMode: Bool) -> some View {
        Button(action: { onSelect(isPlanningMode) }) {
            HStack(spacing: 10) {
                Image(systemName: self.isPlanning == isPlanningMode ? "checkmark" : "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .frame(width: 12)

                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(foregroundStyle(for: isPlanningMode))
                    .frame(width: 14)

                Text(title)
                    .font(Fonts.primary(size: 13))
                    .foregroundStyle(foregroundStyle(for: isPlanningMode))

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground(for: isPlanningMode))
        .onHover { isHovered in
            hoveredMode = isHovered ? isPlanningMode : nil
        }
        .pointerCursor()
    }

    private func foregroundStyle(for isPlanningMode: Bool) -> Color {
        if isPlanning == isPlanningMode || hoveredMode == isPlanningMode {
            return theme.text
        }

        return theme.textMuted
    }

    private func rowBackground(for isPlanningMode: Bool) -> Color {
        hoveredMode == isPlanningMode ? theme.accent.opacity(0.08) : .clear
    }
}
