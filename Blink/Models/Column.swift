import Foundation

struct Column: Identifiable, Equatable, Hashable, Codable {
    let id: String
    var tabIds: [String]  // ordered top-to-bottom
}
