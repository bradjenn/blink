import SwiftUI

struct BrowserAddressBarSuggestionsView: View {
    @Environment(\.theme) private var theme

    let entries: [BrowserHistoryEntry]
    let highlightedID: String?
    let onSelect: (BrowserHistoryEntry) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(entries) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: entry.isLocal ? "network" : "clock.arrow.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(entry.isLocal ? theme.accent : theme.textDim)
                            .frame(width: 14)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.displayTitle)
                                .font(Fonts.primary(size: 12, weight: .medium))
                                .foregroundStyle(theme.text)
                                .lineLimit(1)

                            if entry.displayTitle != entry.urlString {
                                Text(entry.urlString)
                                    .font(Fonts.primary(size: 11))
                                    .foregroundStyle(theme.textDim)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(highlightedID == entry.id ? theme.accent.opacity(0.16) : .clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(highlightedID == entry.id ? theme.accent.opacity(0.38) : .clear, lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.bg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.border.opacity(0.9), lineWidth: 1)
        )
    }
}
