import Foundation

enum BrowserEngine: String, Codable, Equatable, Hashable {
    case webKit
    case chromium
}

enum BrowserEngineSelection {
    // Chromium is the target direction for this branch, but WebKit remains the
    // active runtime until CEF packaging and process integration are in place.
    static let active: BrowserEngine = .webKit
}
