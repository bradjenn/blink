import SwiftUI

struct BrowserDownloadsPopoverView: View {
    @Environment(\.theme) private var theme

    let downloads: [BrowserDownloadItem]
    let onOpen: (BrowserDownloadItem) -> Void
    let onReveal: (BrowserDownloadItem) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Downloads")
                    .font(Fonts.primary(size: 12, weight: .bold))
                    .foregroundStyle(theme.text)

                Spacer(minLength: 0)

                if !downloads.isEmpty {
                    Button("Clear") {
                        onClear()
                    }
                    .buttonStyle(.plain)
                    .font(Fonts.primary(size: 11))
                    .foregroundStyle(theme.textDim)
                    .pointerCursor()
                    .help("Clear Blink download history")
                }
            }

            if downloads.isEmpty {
                Text("No downloads yet")
                    .font(Fonts.primary(size: 11))
                    .foregroundStyle(theme.textDim)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 6) {
                        ForEach(downloads) { download in
                            BrowserDownloadRow(
                                download: download,
                                onOpen: { onOpen(download) },
                                onReveal: { onReveal(download) }
                            )
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(12)
        .frame(width: 336, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.bg.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }
}

private struct BrowserDownloadRow: View {
    @Environment(\.theme) private var theme

    let download: BrowserDownloadItem
    let onOpen: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 4) {
                Text(download.fileName)
                    .font(Fonts.primary(size: 11.5, weight: .regular))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                if let progressFraction = download.progressFraction, download.isInProgress {
                    ProgressView(value: progressFraction)
                        .progressViewStyle(.linear)
                        .tint(theme.accent)
                }

                Text(download.statusText)
                    .font(Fonts.primary(size: 10))
                    .foregroundStyle(theme.textDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if download.isComplete {
                Button(action: onReveal) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textDim)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Reveal in Finder")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.bg2.opacity(0.82))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if download.isComplete {
                onOpen()
            } else if download.destinationURL != nil {
                onReveal()
            }
        }
        .pointerCursor()
    }

    private var iconName: String {
        if download.isComplete {
            return "checkmark.circle.fill"
        }
        if download.isCanceled || download.isInterrupted {
            return "exclamationmark.circle.fill"
        }
        return "arrow.down.circle.fill"
    }

    private var iconColor: Color {
        if download.isComplete {
            return .green
        }
        if download.isCanceled || download.isInterrupted {
            return .orange
        }
        return theme.accent
    }
}
