import SwiftUI

@Observable
final class ThemeManager {
    var activeTheme: Theme = .cyberpunk
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
