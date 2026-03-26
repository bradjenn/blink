import SwiftUI

struct PermissionLevelMenu: View {
    @Environment(\.theme) private var theme

    let selectedLevel: PermissionLevel
    let onSelect: (PermissionLevel) -> Void

    @State private var hoveredLevel: PermissionLevel?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(PermissionLevel.allCases.enumerated()), id: \.element) { index, level in
                Button(action: { onSelect(level) }) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selectedLevel == level ? "checkmark" : "")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .frame(width: 12)
                            .padding(.top, 2)

                        Image(systemName: level.iconName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(foregroundStyle(for: level))
                            .frame(width: 14)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.displayName)
                                .font(Fonts.primary(size: 13))
                                .foregroundStyle(foregroundStyle(for: level))
                                .lineLimit(1)

                            Text(level.description)
                                .font(Fonts.primary(size: 11))
                                .foregroundStyle(theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(rowBackground(for: level))
                .onHover { isHovered in
                    hoveredLevel = isHovered ? level : nil
                }
                .pointerCursor()

                if index < PermissionLevel.allCases.count - 1 {
                    Divider()
                        .overlay(theme.border)
                }
            }
        }
        .frame(width: 240)
        .background(theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        .padding(.top, 4)
    }

    private func foregroundStyle(for level: PermissionLevel) -> Color {
        if selectedLevel == level || hoveredLevel == level {
            return theme.text
        }
        return theme.textMuted
    }

    private func rowBackground(for level: PermissionLevel) -> Color {
        hoveredLevel == level ? theme.accent.opacity(0.08) : .clear
    }
}

struct EffortLevelMenu: View {
    @Environment(\.theme) private var theme

    let selectedLevel: EffortLevel
    let onSelect: (EffortLevel) -> Void

    @State private var hoveredLevel: EffortLevel?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(EffortLevel.allCases.reversed().enumerated()), id: \.element) { index, level in
                Button(action: { onSelect(level) }) {
                    HStack(spacing: 10) {
                        Image(systemName: selectedLevel == level ? "checkmark" : "")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .frame(width: 12)

                        Text(level == .high ? "\(level.displayName) (default)" : level.displayName)
                            .font(Fonts.primary(size: 13))
                            .foregroundStyle(foregroundStyle(for: level))
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(rowBackground(for: level))
                .onHover { isHovered in
                    hoveredLevel = isHovered ? level : nil
                }
                .pointerCursor()

                if index < EffortLevel.allCases.count - 1 {
                    Divider()
                        .overlay(theme.border)
                }
            }
        }
        .frame(width: 200)
        .background(theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        .padding(.top, 4)
    }

    private func foregroundStyle(for level: EffortLevel) -> Color {
        if selectedLevel == level || hoveredLevel == level {
            return theme.text
        }
        return theme.textMuted
    }

    private func rowBackground(for level: EffortLevel) -> Color {
        hoveredLevel == level ? theme.accent.opacity(0.08) : .clear
    }
}
