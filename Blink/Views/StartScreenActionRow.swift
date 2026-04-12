import SwiftUI

struct StartScreenActionRow: View {
    @Environment(\.theme) private var theme

    let icon: String
    let label: String
    let keyHint: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var foregroundColor: Color {
        guard isEnabled else { return theme.textDim.opacity(0.5) }
        return isHovered ? theme.text : theme.textMuted
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(icon)
                    .font(Fonts.primary(size: 14, weight: .bold))
                    .foregroundStyle(isEnabled ? theme.accent : theme.textDim.opacity(0.4))
                    .frame(width: 18, alignment: .center)

                Text(label)
                    .font(Fonts.primary(size: 14))
                    .foregroundStyle(foregroundColor)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(keyHint)
                    .font(Fonts.primary(size: 14))
                    .foregroundStyle(
                        isEnabled
                            ? (isHovered ? theme.text : theme.accent)
                            : theme.textDim.opacity(0.4)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.bg.opacity(isHovered ? 0.2 : 0.001))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(theme.accent.opacity(isHovered ? 0.34 : 0), lineWidth: 1)
                )
        )
        .onHover { isHovered = $0 }
        .pointerCursor()
        .accessibilityLabel("\(label), key \(keyHint)")
    }
}
