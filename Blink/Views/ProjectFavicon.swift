import SwiftUI

/// Avatar-style project icon — circular with initials fallback.
struct ProjectFavicon: View {
    @Environment(\.theme) private var theme
    let projectName: String
    let size: CGFloat

    init(projectName: String = "", size: CGFloat = 24) {
        self.projectName = projectName
        self.size = size
    }

    private var initial: String {
        String(projectName.prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.border)

            if initial.isEmpty {
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
}
