import Foundation

enum ManagedCommandStatus: String, Equatable, Hashable {
    case running
    case stopped
}

struct ManagedCommandState: Equatable, Hashable {
    var status: ManagedCommandStatus
}

struct AppTab: Identifiable, Equatable, Hashable {
    let id: String
    let type: String
    var label: String
    var defaultLabel: String
    let projectId: String
    var command: String? = nil
    var role: String? = nil
    var workingDirectory: String? = nil
    var projectSetupPaneId: String? = nil

    var isShell: Bool { type == "shell" }
    var isManagedCommand: Bool { isShell && command != nil }
}
