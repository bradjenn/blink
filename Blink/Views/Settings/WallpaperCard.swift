import SwiftUI

struct WallpaperCard: View {
    @Environment(\.theme) private var theme

    let name: String
    let filename: String?  // e.g. "ship-at-sea.jpg" — loaded from bundle
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottom) {
                if let filename, let image = Self.loadBundleImage(filename) {
                    GeometryReader { geo in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                    .frame(height: 100)
                } else {
                    theme.bg2
                        .frame(height: 100)
                }

                Text(name)
                    .font(Fonts.primary(size: 11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.5))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Load an image from the app bundle by filename (e.g. "ship-at-sea.jpg").
    private static func loadBundleImage(_ filename: String) -> Image? {
        let parts = filename.split(separator: ".")
        guard parts.count == 2,
              let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1])),
              let nsImage = NSImage(contentsOf: url) else {
            return nil
        }
        return Image(nsImage: nsImage)
    }
}
