import Foundation

enum CursorStyle: String, CaseIterable, Codable {
    case block = "block"
    case bar = "bar"
    case underline = "underline"

    var displayName: String {
        switch self {
        case .block: "Block"
        case .bar: "Bar"
        case .underline: "Underline"
        }
    }
}
