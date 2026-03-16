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
                    .font(Fonts.primary(size: 12))
                    .foregroundStyle(theme.textDim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.border.opacity(isEnabled ? 0.65 : 0.3))
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered && isEnabled ? Color.white.opacity(0.045) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.border.opacity(isHovered && isEnabled ? 0.75 : 0.0), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .accessibilityLabel("\(label), key \(keyHint)")
    }
}
