import Foundation

struct Project: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let path: String
    let color: String     // Hex color, reserved for future use
    let createdAt: Date

    /// Home directory path prefix replacement for display.
    var displayPath: String {
        path.replacingOccurrences(
            of: "/Users/\(NSUserName())",
            with: "~"
        )
    }
}

extension Project {
    static let dummy: [Project] = [
        Project(id: "1", name: "blink", path: "/Users/bradley/Code/blink", color: "#c8ff00", createdAt: Date()),
        Project(id: "2", name: "krux", path: "/Users/bradley/Code/krux", color: "#0fc5ed", createdAt: Date()),
        Project(id: "3", name: "api-server", path: "/Users/bradley/Code/api-server", color: "#a277ff", createdAt: Date()),
        Project(id: "4", name: "dotfiles", path: "/Users/bradley/Code/dotfiles", color: "#44ffb1", createdAt: Date()),
    ]
}
