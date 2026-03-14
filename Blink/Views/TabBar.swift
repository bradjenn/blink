import SwiftUI

struct TabBarView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Text("KRUX")
                .font(Fonts.primary(size: 11, weight: .bold))
                .foregroundStyle(theme.textDim)
            Spacer()
        }
        .padding(.leading, Layout.tabBarLogoPaddingLeft)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg2)
        .overlay(alignment: .bottom) {
            theme.border.frame(height: 1)
        }
    }
}
