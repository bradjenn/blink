import SwiftUI

struct ChatProviderMenu: View {
    @Environment(\.theme) private var theme

    let selectedProvider: ChatProvider
    let onSelect: (ChatProvider) -> Void

    @State private var hoveredProvider: ChatProvider?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(ChatProvider.allCases.enumerated()), id: \.element) { index, provider in
                Button(action: { onSelect(provider) }) {
                    HStack(spacing: 10) {
                        Image(systemName: selectedProvider == provider ? "checkmark" : "")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .frame(width: 12)

                        providerIcon(provider)
                            .frame(width: 14, height: 14)

                        Text(provider.displayName)
                            .font(Fonts.primary(size: 13))
                            .foregroundStyle(foregroundStyle(for: provider))
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(rowBackground(for: provider))
                .onHover { isHovered in
                    hoveredProvider = isHovered ? provider : nil
                }
                .pointerCursor()

                if index < ChatProvider.allCases.count - 1 {
                    Divider()
                        .overlay(theme.border)
                }
            }
        }
        .frame(width: 212)
        .background(theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
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
                .foregroundStyle(foregroundStyle(for: provider))
        }
    }

    private func foregroundStyle(for provider: ChatProvider) -> Color {
        if selectedProvider == provider || hoveredProvider == provider {
            return theme.text
        }

        return theme.textMuted
    }

    private func rowBackground(for provider: ChatProvider) -> Color {
        hoveredProvider == provider ? theme.accent.opacity(0.08) : .clear
    }
}
