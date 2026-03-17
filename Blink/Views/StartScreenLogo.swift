import SwiftUI

struct StartScreenLogo: View {
    @Environment(\.theme) private var theme

    private static let asciiArt = """
    ██████╗ ██╗     ██╗███╗   ██╗██╗  ██╗
    ██╔══██╗██║     ██║████╗  ██║██║ ██╔╝
    ██████╔╝██║     ██║██╔██╗ ██║█████╔╝
    ██╔══██╗██║     ██║██║╚██╗██║██╔═██╗
    ██████╔╝███████╗██║██║ ╚████║██║  ██╗
    ╚═════╝ ╚══════╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝
    """

    var body: some View {
        Text(Self.asciiArt)
            .font(.custom("MesloLGSNFM-Bold", size: 16))
            .lineSpacing(-9)
            .tracking(0)
            .foregroundStyle(theme.accent)
            .shadow(color: theme.accent.opacity(0.16), radius: 10)
            .fixedSize()
            .accessibilityHidden(true)
    }
}
