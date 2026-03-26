import Foundation

enum ChatRuntimeEventKind: String, Codable, Hashable {
    case commandExecution
    case reasoning
    case planUpdate
    case diffUpdate
    case approvalRequest
    case userInputRequest
    case toolSummary
    case info
    case warning
    case error
}

enum ChatRuntimeEventStatus: String, Codable, Hashable {
    case pending
    case inProgress
    case completed
    case failed
    case resolved
}

struct ChatRuntimeQuestionOption: Equatable, Hashable, Codable {
    let id: String
    let label: String
    let description: String?
}

struct ChatRuntimeQuestion: Equatable, Hashable, Codable {
    let id: String
    let header: String
    let prompt: String
    let options: [ChatRuntimeQuestionOption]
}

struct ChatRuntimeDiffFile: Equatable, Hashable, Codable {
    let path: String
    let additions: Int?
    let deletions: Int?
}

struct ChatTurnRuntimeEvent: Equatable, Hashable {
    let id: String
    let kind: ChatRuntimeEventKind
    let title: String
    let detail: String?
    let output: String?
    let status: ChatRuntimeEventStatus
    let exitCode: Int?
    let requestId: String?
    let questions: [ChatRuntimeQuestion]
    let changedFiles: [ChatRuntimeDiffFile]
}

struct ChatMessageRuntimeEvent: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let threadId: String
    let messageId: String
    let kind: ChatRuntimeEventKind
    let title: String
    let detail: String?
    let output: String?
    let status: ChatRuntimeEventStatus
    let exitCode: Int?
    let requestId: String?
    let questions: [ChatRuntimeQuestion]
    let changedFiles: [ChatRuntimeDiffFile]
    let createdAt: Date
}

extension ChatTurnRuntimeEvent {
    var workItem: ChatTurnWorkItem? {
        let kind: ChatWorkItemKind
        switch self.kind {
        case .commandExecution:
            kind = .commandExecution
        case .reasoning:
            kind = .reasoning
        case .planUpdate:
            kind = .plan
        default:
            return nil
        }

        let status: ChatWorkItemStatus
        switch self.status {
        case .pending, .inProgress:
            status = .inProgress
        case .failed:
            status = .failed
        case .completed, .resolved:
            status = .completed
        }

        return ChatTurnWorkItem(
            id: id,
            kind: kind,
            title: title,
            detail: detail,
            output: output,
            status: status,
            exitCode: exitCode
        )
    }
}

extension ChatMessageRuntimeEvent {
    var workItem: ChatMessageWorkItem? {
        let kind: ChatWorkItemKind
        switch self.kind {
        case .commandExecution:
            kind = .commandExecution
        case .reasoning:
            kind = .reasoning
        case .planUpdate:
            kind = .plan
        default:
            return nil
        }

        let status: ChatWorkItemStatus
        switch self.status {
        case .pending, .inProgress:
            status = .inProgress
        case .failed:
            status = .failed
        case .completed, .resolved:
            status = .completed
        }

        return ChatMessageWorkItem(
            id: id,
            threadId: threadId,
            messageId: messageId,
            kind: kind,
            title: title,
            detail: detail,
            output: output,
            status: status,
            exitCode: exitCode,
            createdAt: createdAt
        )
    }
}
