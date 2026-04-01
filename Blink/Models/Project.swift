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

enum ProjectSetupPaneKind: String, Codable, Hashable {
    case shell
    case command
    case chat
    case browser
}

struct ProjectSetupPane: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let kind: ProjectSetupPaneKind
    var label: String
    var role: String?
    var command: String?
    var workingDirectory: String?
    var browserState: BrowserPaneState?
}

struct ProjectSetupColumn: Identifiable, Equatable, Hashable, Codable {
    let id: String
    var paneIds: [String]
}

struct ProjectSetup: Equatable, Hashable, Codable {
    let projectId: String
    var updatedAt: Date
    var columns: [ProjectSetupColumn]
    var panes: [ProjectSetupPane]
}
