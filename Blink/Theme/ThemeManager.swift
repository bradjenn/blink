import SwiftUI

@Observable
final class ThemeManager {
    var activeTheme: Theme = .cyberpunk

    func setTheme(id: String) {
        if let theme = Theme.allThemes.first(where: { $0.id == id }) {
            activeTheme = theme
        }
    }
}

// SwiftUI Environment key for the active theme
private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: Theme = .cyberpunk
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}
