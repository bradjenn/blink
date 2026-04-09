import SwiftUI

struct BlinkModalBackdrop: View {
    let onDismiss: () -> Void
    let accessibilityLabel: String

    var body: some View {
        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .onTapGesture { onDismiss() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(accessibilityLabel)
    }
}

struct BlinkModalPanel<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let width: CGFloat
    let cornerRadius: CGFloat
    let content: Content

    init(
        width: CGFloat,
        cornerRadius: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.width = width
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: width)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.36), radius: 22, y: 12)
    }

    private var panelBackground: some ShapeStyle {
        if store.hasWallpaper {
            AnyShapeStyle(theme.bg.opacity(store.backgroundOpacity))
        } else {
            AnyShapeStyle(theme.bg.opacity(0.97))
        }
    }
}

private struct BlinkSelectableRowModifier: ViewModifier {
    @Environment(\.theme) private var theme

    let isSelected: Bool
    let isHovered: Bool

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(background)
    }

    private var background: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(theme.accent.opacity(0.12))
        }

        if isHovered {
            return AnyShapeStyle(theme.accent.opacity(0.08))
        }

        return AnyShapeStyle(Color.clear)
    }
}

extension View {
    func blinkSelectableRow(isSelected: Bool, isHovered: Bool) -> some View {
        modifier(BlinkSelectableRowModifier(isSelected: isSelected, isHovered: isHovered))
    }
}
