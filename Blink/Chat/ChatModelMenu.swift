import SwiftUI

struct ChatModelMenu: View {
    @Environment(\.theme) private var theme

    let options: [(label: String, value: String)]
    let selectedValue: String
    let iconName: String
    let onSelect: (String) -> Void

    @State private var hoveredValue: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button(action: { onSelect(option.value) }) {
                    HStack(spacing: 10) {
                        Image(systemName: selectedValue == option.value ? "checkmark" : "")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .frame(width: 12)

                        Image(systemName: iconName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(foregroundStyle(for: option.value))
                            .frame(width: 14)

                        Text(option.label)
                            .font(Fonts.primary(size: 13))
                            .foregroundStyle(foregroundStyle(for: option.value))
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(rowBackground(for: option.value))
                .onHover { isHovered in
                    hoveredValue = isHovered ? option.value : nil
                }
                .pointerCursor()

                if index < options.count - 1 {
                    Divider()
                        .overlay(theme.border)
                }
            }
        }
        .frame(width: 228)
        .background(theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        .padding(.top, 4)
    }

    private func foregroundStyle(for value: String) -> Color {
        if selectedValue == value || hoveredValue == value {
            return theme.text
        }

        return theme.textMuted
    }

    private func rowBackground(for value: String) -> Color {
        hoveredValue == value ? theme.accent.opacity(0.08) : .clear
    }
}
