import SwiftUI

struct BlinkActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case secondaryCompact
    }

    @Environment(\.theme) private var theme

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        BlinkActionButtonBody(
            configuration: configuration,
            kind: kind
        )
    }
}

private struct BlinkActionButtonBody: View {
    @Environment(\.theme) private var theme

    let configuration: ButtonStyle.Configuration
    let kind: BlinkActionButtonStyle.Kind

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(font)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(background)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
            .pointerCursor()
    }

    private var font: Font {
        switch kind {
        case .secondaryCompact:
            return Fonts.primary(size: 11, weight: .bold)
        case .primary, .secondary:
            return Fonts.primary(size: 12, weight: .bold)
        }
    }

    private var horizontalPadding: CGFloat {
        switch kind {
        case .secondaryCompact:
            return 12
        case .primary, .secondary:
            return 16
        }
    }

    private var verticalPadding: CGFloat {
        switch kind {
        case .secondaryCompact:
            return 8
        case .primary, .secondary:
            return 10
        }
    }

    private var cornerRadius: CGFloat {
        switch kind {
        case .secondaryCompact:
            return 9
        case .primary, .secondary:
            return 10
        }
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return theme.bg
        case .secondary, .secondaryCompact:
            return theme.text
        }
    }

    private var backgroundFill: Color {
        switch kind {
        case .primary:
            if configuration.role == .destructive {
                return theme.danger.opacity(configuration.isPressed ? 0.82 : isHovered ? 0.96 : 0.9)
            } else {
                return theme.accent.opacity(configuration.isPressed ? 0.82 : isHovered ? 0.96 : 0.9)
            }
        case .secondary, .secondaryCompact:
            return theme.bg2.opacity(configuration.isPressed ? 0.82 : isHovered ? 0.7 : 0.54)
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(backgroundFill)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(borderColor, lineWidth: 1)
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return Color.clear
        case .secondary, .secondaryCompact:
            return isHovered ? theme.accent.opacity(0.45) : theme.border
        }
    }
}
