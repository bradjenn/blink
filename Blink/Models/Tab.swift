import Foundation

enum ManagedCommandStatus: String, Equatable, Hashable {
    case running
    case stopped
}

struct ManagedCommandState: Equatable, Hashable {
    var status: ManagedCommandStatus
}

enum ManagedAIPaneKind: String, Equatable, Hashable {
    case codex
    case claude
    case claudeYolo

    init?(command: String) {
        switch command {
        case "codex":
            self = .codex
        case "claude":
            self = .claude
        case "claude --dangerously-skip-permissions":
            self = .claudeYolo
        default:
            return nil
        }
    }

    init?(submittedLine: String) {
        let trimmed = submittedLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed == "codex" || trimmed.hasPrefix("codex ") {
            self = .codex
            return
        }

        if trimmed == "claude --dangerously-skip-permissions"
            || trimmed.hasPrefix("claude --dangerously-skip-permissions ") {
            self = .claudeYolo
            return
        }

        if trimmed == "claude" || trimmed.hasPrefix("claude ") {
            self = .claude
            return
        }

        return nil
    }

    var displayName: String {
        switch self {
        case .codex:
            "Codex"
        case .claude, .claudeYolo:
            "Claude Code"
        }
    }

    var command: String {
        switch self {
        case .codex:
            "codex"
        case .claude:
            "claude"
        case .claudeYolo:
            "claude --dangerously-skip-permissions"
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
    var chatThreadId: String? = nil
    var role: String? = nil
    var workingDirectory: String? = nil
    var projectSetupPaneId: String? = nil

    var isShell: Bool { type == "shell" }
    var isChat: Bool { type == "chat" }
    var isManagedCommand: Bool { isShell && command != nil }
    var managedAIPaneKind: ManagedAIPaneKind? {
        guard let command else { return nil }
        return ManagedAIPaneKind(command: command)
    }
    var isManagedAIPane: Bool { managedAIPaneKind != nil }
}
