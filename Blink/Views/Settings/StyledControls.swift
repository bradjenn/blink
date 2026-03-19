import SwiftUI

// MARK: - Dropdown

struct StyledDropdown<T: Hashable>: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let selection: T
    let options: [T]
    let label: (T) -> String
    let onChange: (T) -> Void
    var fontPreview: Bool = false

    @State private var isOpen = false
    @State private var isHovered = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private var filteredOptions: [T] {
        guard !searchText.isEmpty else { return options }
        return options.filter { label($0).localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Button(action: { isOpen.toggle() }) {
            HStack(spacing: 8) {
                Text(label(selection))
                    .font(Fonts.primary(size: 13, family: store.uiFontFamily))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textDim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isHovered ? theme.textMuted.opacity(0.3) : theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                if options.count > 10 {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textDim)
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(Fonts.primary(size: 13, family: store.uiFontFamily))
                            .foregroundStyle(theme.text)
                            .focused($searchFocused)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)

                    Divider().opacity(0.3)
                }

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(filteredOptions, id: \.self) { option in
                            DropdownRow(
                                label: label(option),
                                isSelected: option == selection,
                                fontPreview: fontPreview,
                                action: {
                                    onChange(option)
                                    isOpen = false
                                    searchText = ""
                                }
                            )
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 300)
            }
            .frame(width: 280)
            .background(VisualEffectBackground(material: .popover, blendingMode: .behindWindow))
            .onAppear {
                if options.count > 10 {
                    searchFocused = true
                }
            }
            .onDisappear { searchText = "" }
        }
    }
}

private struct DropdownRow: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let label: String
    let isSelected: Bool
    var fontPreview: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(fontPreview
                        ? .custom(label, size: 13)
                        : Fonts.primary(size: 13, family: store.uiFontFamily))
                    .foregroundStyle(isSelected ? theme.text : isHovered ? theme.text : theme.textMuted)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.08) : isSelected ? Color.white.opacity(0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerCursor()
    }
}

// MARK: - Segment Picker

struct StyledSegmentPicker<T: Hashable>: View {
    @Environment(\.theme) private var theme

    let options: [T]
    let selection: T
    let label: (T) -> String
    let onChange: (T) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                SegmentButton(
                    label: label(option),
                    isActive: option == selection,
                    action: { onChange(option) }
                )
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 1)
        )
    }
}

private struct SegmentButton: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let label: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Fonts.primary(size: 13, family: store.uiFontFamily))
                .foregroundStyle(isActive ? theme.text : isHovered ? theme.text : theme.textMuted)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.white.opacity(0.12) : isHovered ? Color.white.opacity(0.06) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isActive)
    }
}

// MARK: - Stepper

struct StyledStepper: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let value: Int
    let range: ClosedRange<Int>
    let label: String
    let onChange: (Int) -> Void

    @State private var minusHovered = false
    @State private var plusHovered = false

    var body: some View {
        HStack(spacing: 0) {
            stepperButton(systemName: "minus", hovered: $minusHovered, disabled: value <= range.lowerBound) {
                onChange(value - 1)
            }

            Text(label)
                .font(Fonts.primary(size: 13, family: store.uiFontFamily))
                .foregroundStyle(theme.text)
                .frame(minWidth: 48)
                .frame(height: 30)
                .background(Color.white.opacity(0.08))

            stepperButton(systemName: "plus", hovered: $plusHovered, disabled: value >= range.upperBound) {
                onChange(value + 1)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func stepperButton(systemName: String, hovered: Binding<Bool>, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(disabled ? theme.textDim.opacity(0.4) : hovered.wrappedValue ? theme.text : theme.textMuted)
                .frame(width: 30, height: 30)
                .background(hovered.wrappedValue && !disabled ? Color.white.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovered.wrappedValue = $0 }
        .pointerCursor()
    }
}

// MARK: - Text Field

struct StyledTextField: View {
    @Environment(\.theme) private var theme

    @Binding var text: String
    let placeholder: String

    @State private var isFocused = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .focused($fieldFocused)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(fieldFocused ? theme.accent.opacity(0.6) : theme.border, lineWidth: 1)
            )
            .onChange(of: fieldFocused) { _, new in isFocused = new }
            .animation(.easeOut(duration: 0.12), value: fieldFocused)
    }
}

// MARK: - NSVisualEffectView wrapper

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
