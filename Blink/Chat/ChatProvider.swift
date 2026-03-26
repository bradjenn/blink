import Foundation

struct ChatModelOption: Identifiable, Equatable, Hashable {
    let label: String
    let value: String

    var id: String {
        value.isEmpty ? "default-\(label)" : value
    }
}

struct ChatComposerProviderTraits: Equatable, Hashable {
    let defaultModelLabel: String
    let modelOptions: [ChatModelOption]
    let supportsEffort: Bool
    let supportsNativeAttachments: Bool
}

enum ChatProvider: String, CaseIterable, Codable, Hashable {
    case codex
    case claude
    case secondOpinion = "allHands"

    var displayName: String {
        switch self {
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        case .secondOpinion:
            "Planning Session"
        }
    }

    var composerTraits: ChatComposerProviderTraits {
        switch self {
        case .codex:
            ChatComposerProviderTraits(
                defaultModelLabel: "Default",
                modelOptions: [
                    ChatModelOption(label: "Default", value: ""),
                    ChatModelOption(label: "GPT-5.4", value: "gpt-5.4"),
                    ChatModelOption(label: "GPT-5.3 Codex", value: "gpt-5.3-codex"),
                    ChatModelOption(label: "GPT-5.3 Codex Spark", value: "gpt-5.3-codex-spark"),
                    ChatModelOption(label: "GPT-5.2 Codex", value: "gpt-5.2-codex"),
                    ChatModelOption(label: "GPT-5.2", value: "gpt-5.2"),
                ],
                supportsEffort: true,
                supportsNativeAttachments: true
            )
        case .claude:
            ChatComposerProviderTraits(
                defaultModelLabel: "Default",
                modelOptions: [
                    ChatModelOption(label: "Default", value: ""),
                    ChatModelOption(label: "Opus 4.6", value: "opus"),
                    ChatModelOption(label: "Sonnet 4.6", value: "sonnet"),
                    ChatModelOption(label: "Haiku 4.5", value: "haiku"),
                ],
                supportsEffort: true,
                supportsNativeAttachments: false
            )
        case .secondOpinion:
            .init(
                defaultModelLabel: "Default",
                modelOptions: ChatProvider.codex.composerTraits.modelOptions,
                supportsEffort: false,
                supportsNativeAttachments: false
            )
        }
    }

    var defaultModelLabel: String {
        composerTraits.defaultModelLabel
    }

    var supportsEffort: Bool {
        composerTraits.supportsEffort
    }
}

enum PermissionLevel: String, CaseIterable, Codable, Hashable {
    case readOnly
    case workspaceWrite
    case fullAccess

    var displayName: String {
        switch self {
        case .readOnly:
            "Read only"
        case .workspaceWrite:
            "Workspace write"
        case .fullAccess:
            "Full access"
        }
    }

    var description: String {
        switch self {
        case .readOnly:
            "No edits or commands."
        case .workspaceWrite:
            "Can edit files inside the project."
        case .fullAccess:
            "No sandbox. Full machine access."
        }
    }

    var iconName: String {
        switch self {
        case .readOnly:
            "lock.fill"
        case .workspaceWrite:
            "square.and.pencil"
        case .fullAccess:
            "lock.open.fill"
        }
    }

    static var defaultLevel: PermissionLevel { .readOnly }
}

enum EffortLevel: String, CaseIterable, Codable, Hashable {
    case low
    case medium
    case high
    case max

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .max: "Extra High"
        }
    }

    var shortLabel: String {
        switch self {
        case .low: "Low"
        case .medium: "Med"
        case .high: "High"
        case .max: "Max"
        }
    }

    var cliValue: String {
        rawValue
    }

    static var defaultLevel: EffortLevel { .high }
}
