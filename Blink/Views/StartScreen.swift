import SwiftUI

struct StartScreen: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(theme.textDim.opacity(0.5))
            Text("No project selected")
                .font(Fonts.primary(size: 16))
                .foregroundStyle(theme.textMuted)
            Text("Select a project from the sidebar")
                .font(Fonts.primary(size: 13))
                .foregroundStyle(theme.textDim)
        }
    }
}
