import SwiftUI

struct WorkspaceSidebarPanel: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    var body: some View {
        SidebarView()
            .frame(maxHeight: .infinity)
            .background(AnyShapeStyle(Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(store.sidebarFocused ? theme.accent.opacity(0.85) : theme.border, lineWidth: 1)
            )
            .onAppear {
                store.completePendingSidebarRevealFocus()
            }
    }
}
