import Foundation

enum AppSurfaceKind: String, Codable, Equatable, Hashable {
    case terminal
    case chat
    case browser

    init(typeValue: String) {
        switch typeValue {
        case "browser":
            self = .browser
        case "chat":
            self = .chat
        default:
            self = .terminal
        }
    }
}

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
    let kind: AppSurfaceKind
    var label: String
    var defaultLabel: String
    let projectId: String
    var command: String? = nil
    var role: String? = nil
    var workingDirectory: String? = nil
    var projectSetupPaneId: String? = nil
    var browserState: BrowserTabState? = nil

    init(
        id: String,
        kind: AppSurfaceKind,
        label: String,
        defaultLabel: String,
        projectId: String,
        command: String? = nil,
        role: String? = nil,
        workingDirectory: String? = nil,
        projectSetupPaneId: String? = nil,
        browserState: BrowserTabState? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.defaultLabel = defaultLabel
        self.projectId = projectId
        self.command = command
        self.role = role
        self.workingDirectory = workingDirectory
        self.projectSetupPaneId = projectSetupPaneId
        self.browserState = browserState
    }

    init(
        id: String,
        type: String,
        label: String,
        defaultLabel: String,
        projectId: String,
        command: String? = nil,
        role: String? = nil,
        workingDirectory: String? = nil,
        projectSetupPaneId: String? = nil,
        browserState: BrowserTabState? = nil
    ) {
        self.init(
            id: id,
            kind: AppSurfaceKind(typeValue: type),
            label: label,
            defaultLabel: defaultLabel,
            projectId: projectId,
            command: command,
            role: role,
            workingDirectory: workingDirectory,
            projectSetupPaneId: projectSetupPaneId,
            browserState: browserState
        )
    }

    var isTerminal: Bool { kind == .terminal }
    var isBrowser: Bool { kind == .browser }
    var isShell: Bool { isTerminal }
    var isManagedCommand: Bool { isShell && command != nil }
}
