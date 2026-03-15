import SwiftUI

struct ThemeCard: View {
    let theme: Theme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle().fill(theme.accent).frame(width: 12, height: 12)
                    Circle().fill(theme.accent2).frame(width: 12, height: 12)
                    Circle().fill(theme.bg).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(theme.border, lineWidth: 1))
                }

                Text(theme.name)
                    .font(Fonts.primary(size: 13))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
