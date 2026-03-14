import SwiftUI

struct ProjectFavicon: View {
    @Environment(\.theme) private var theme
    let size: CGFloat

    init(size: CGFloat = 15) {
        self.size = size
    }

    var body: some View {
        Image(systemName: "folder")
            .font(.system(size: size, weight: .light))
            .foregroundStyle(theme.textMuted)
            .frame(width: size, height: size)
    }
}
