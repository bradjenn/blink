import Foundation

enum ManagedCommandStatus: String, Equatable, Hashable {
    case running
    case stopped
}

struct ManagedCommandState: Equatable, Hashable {
    var status: ManagedCommandStatus
}

enum ShellDetectedAIPaneKind: String, Equatable, Hashable, CaseIterable {
    case claude
    case codex
    case opencode

    init?(submittedLine: String) {
        let trimmed = submittedLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed == "claude" || trimmed.hasPrefix("claude ") {
            self = .claude
            return
        }

        if trimmed == "codex" || trimmed.hasPrefix("codex ") {
            self = .codex
            return
        }

        if trimmed == "opencode" || trimmed.hasPrefix("opencode ") {
            self = .opencode
            return
        }

        return nil
    }

    var displayName: String {
        switch self {
        case .claude:
            "Claude Code"
        case .codex:
            "Codex"
        case .opencode:
            "OpenCode"
        }
    }
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
