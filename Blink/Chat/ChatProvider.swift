import Foundation

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

    var defaultModelLabel: String {
        switch self {
        case .codex:
            "Codex Default"
        case .claude:
            "Claude Default"
        case .secondOpinion:
            "Codex Default"
        }
    }
}
