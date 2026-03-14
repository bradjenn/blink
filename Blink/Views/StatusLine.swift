import SwiftUI

struct StatusLine: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
        .overlay(alignment: .top) {
            theme.border.frame(height: 1)
        }
    }
}
