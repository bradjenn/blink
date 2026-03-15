import SwiftUI
import AppKit

/// Project icon — rounded square with favicon or initial fallback.
struct ProjectFavicon: View {
    @Environment(\.theme) private var theme
    let projectName: String
    let projectPath: String
    let size: CGFloat

    init(projectName: String = "", projectPath: String = "", size: CGFloat = 24) {
        self.projectName = projectName
        self.projectPath = projectPath
        self.size = size
    }

    private var initial: String {
        String(projectName.prefix(1)).uppercased()
    }

    private var cornerRadius: CGFloat {
        size * 0.22
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(theme.border)

            if let image = Self.loadFavicon(projectPath: projectPath, size: size) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else if initial.isEmpty {
                Image(systemName: "folder")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(theme.textMuted)
            } else {
                Text(initial)
                    .font(Fonts.primary(size: size * 0.42, weight: .bold).leading(.tight))
                    .foregroundStyle(theme.text)
            }
        }
        .frame(width: size, height: size)
    }

    /// Common favicon locations in web projects.
    private static let faviconPaths = [
        "public/favicon.ico",
        "public/favicon.png",
        "public/favicon.svg",
        "public/icon.png",
        "public/logo.png",
        "app/favicon.ico",
        "app/icon.png",
        "src/favicon.ico",
        "src/favicon.png",
        "assets/icon.png",
        "assets/logo.png",
        "build/icon.png",
        "icon.png",
        "logo.png",
        "favicon.ico",
        "favicon.png",
    ]

    /// Cached favicon lookups to avoid repeated file system checks.
    private static var cache: [String: NSImage?] = [:]

    /// Try to load a favicon from common project locations.
    private static func loadFavicon(projectPath: String, size: CGFloat) -> NSImage? {
        if let cached = cache[projectPath] {
            return cached
        }

        for relativePath in faviconPaths {
            let fullPath = (projectPath as NSString).appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: fullPath),
               let image = NSImage(contentsOfFile: fullPath) {
                // Resize for efficiency
                let resized = image
                cache[projectPath] = resized
                return resized
            }
        }

        cache[projectPath] = nil
        return nil
    }
}
