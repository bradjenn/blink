import Foundation

struct Column: Identifiable, Equatable, Hashable {
    let id: String
    var tabIds: [String]  // ordered top-to-bottom
}
