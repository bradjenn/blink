import Foundation

enum BrowserEngine: String, Codable, Equatable, Hashable {
    case webKit
    case chromium
}

enum BrowserEngineSelection {
    static let active: BrowserEngine = .chromium
}
