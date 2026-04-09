import SwiftUI
import AppKit

/// Workspace icon — rounded square with favicon or initial fallback.
struct WorkspaceFavicon: View {
    @Environment(\.theme) private var theme
    let workspaceName: String
    let workspacePath: String
    let size: CGFloat

    init(workspaceName: String = "", workspacePath: String = "", size: CGFloat = 24) {
        self.workspaceName = workspaceName
        self.workspacePath = workspacePath
        self.size = size
    }

    private var initial: String {
        String(workspaceName.prefix(1)).uppercased()
    }

    private var cornerRadius: CGFloat {
        size * 0.22
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(theme.border)

            if let image = Self.loadFavicon(workspacePath: workspacePath, size: size) {
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

    /// Common favicon locations in web workspaces.
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
    @MainActor private static var cache: [String: NSImage?] = [:]

    /// Try to load a favicon from common workspace locations.
    static func faviconImage(workspacePath: String, size: CGFloat) -> NSImage? {
        if let cached = cache[workspacePath] {
            return cached
        }

        for relativePath in faviconPaths {
            let fullPath = (workspacePath as NSString).appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: fullPath),
               let image = NSImage(contentsOfFile: fullPath) {
                // Resize for efficiency
                let resized = image
                cache[workspacePath] = resized
                return resized
            }
        }

        cache[workspacePath] = nil
        return nil
    }

    private static func loadFavicon(workspacePath: String, size: CGFloat) -> NSImage? {
        faviconImage(workspacePath: workspacePath, size: size)
    }
}
