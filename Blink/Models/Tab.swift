import Foundation

struct Tab: Identifiable, Equatable, Hashable {
    let id: String
    let type: String         // "shell", "tool:claude-code", etc.
    let label: String
    let projectId: String
    var terminalId: String?  // Only for shell tabs
}

extension Tab {
    /// Dummy tabs for testing — 2 for first project, 1 for second, 0 for rest.
    static let dummy: [Tab] = [
        Tab(id: "t1", type: "shell", label: "Terminal 1", projectId: "1", terminalId: "pty-1"),
        Tab(id: "t2", type: "shell", label: "Terminal 2", projectId: "1", terminalId: "pty-2"),
        Tab(id: "t3", type: "shell", label: "Terminal 1", projectId: "2", terminalId: "pty-3"),
    ]
}
