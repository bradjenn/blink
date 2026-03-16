import Foundation

struct Project: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let name: String
    let path: String
    let color: String
    let createdAt: Date

    /// Home directory path prefix replacement for display.
    var displayPath: String {
        path.replacing("/Users/\(NSUserName())", with: "~")
    }
}
