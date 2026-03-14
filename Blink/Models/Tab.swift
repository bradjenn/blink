import Foundation

struct AppTab: Identifiable, Equatable, Hashable {
    let id: String
    let type: String         // "shell", "tool:claude-code", etc.
    let label: String
    let projectId: String
    var terminalId: String?  // Only for shell tabs
}

extension AppTab {
    /// Dummy tabs for testing — 2 for first project, 1 for second, 0 for rest.
    static let dummy: [AppTab] = [
        AppTab(id: "t1", type: "shell", label: "Terminal 1", projectId: "1", terminalId: "pty-1"),
        AppTab(id: "t2", type: "shell", label: "Terminal 2", projectId: "1", terminalId: "pty-2"),
        AppTab(id: "t3", type: "shell", label: "Terminal 1", projectId: "2", terminalId: "pty-3"),
    ]
}
