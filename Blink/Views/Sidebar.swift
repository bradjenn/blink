import SwiftUI

struct SidebarView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading) {
            Text("PROJECTS")
                .font(Fonts.primary(size: 11, weight: .medium))
                .foregroundStyle(theme.textDim)
                .padding(Layout.sidebarHeaderPadding)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.bg2)
        .overlay(alignment: .trailing) {
            theme.border.frame(width: 1)
        }
    }
}
