import SwiftUI

struct AppearanceSettings: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("Appearance")
                .font(Fonts.primary(size: 18, weight: .bold))
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
