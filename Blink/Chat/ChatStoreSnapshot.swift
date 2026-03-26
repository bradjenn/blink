import Foundation

struct ChatStoreSnapshot: Codable {
    var threads: [ChatThread]
    var messages: [ChatMessage]
    var runtimeEvents: [ChatMessageRuntimeEvent]

    init(
        threads: [ChatThread],
        messages: [ChatMessage],
        runtimeEvents: [ChatMessageRuntimeEvent] = []
    ) {
        self.threads = threads
        self.messages = messages
        self.runtimeEvents = runtimeEvents
    }

    private enum CodingKeys: String, CodingKey {
        case threads
        case messages
        case runtimeEvents
        case workItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threads = try container.decodeIfPresent([ChatThread].self, forKey: .threads) ?? []
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        runtimeEvents = try container.decodeIfPresent([ChatMessageRuntimeEvent].self, forKey: .runtimeEvents) ?? []

        if runtimeEvents.isEmpty {
            let legacyWorkItems = try container.decodeIfPresent([ChatMessageWorkItem].self, forKey: .workItems) ?? []
            runtimeEvents = legacyWorkItems.map { item in
                let kind: ChatRuntimeEventKind
                switch item.kind {
                case .commandExecution:
                    kind = .commandExecution
                case .reasoning:
                    kind = .reasoning
                case .plan:
                    kind = .planUpdate
                }

                let status: ChatRuntimeEventStatus
                switch item.status {
                case .inProgress:
                    status = .inProgress
                case .completed:
                    status = .completed
                case .failed:
                    status = .failed
                }

                return ChatMessageRuntimeEvent(
                    id: item.id,
                    threadId: item.threadId,
                    messageId: item.messageId,
                    kind: kind,
                    title: item.title,
                    detail: item.detail,
                    output: item.output,
                    status: status,
                    exitCode: item.exitCode,
                    requestId: nil,
                    questions: [],
                    changedFiles: [],
                    createdAt: item.createdAt
                )
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threads, forKey: .threads)
        try container.encode(messages, forKey: .messages)
        try container.encode(runtimeEvents, forKey: .runtimeEvents)
    }

    static let empty = ChatStoreSnapshot(threads: [], messages: [], runtimeEvents: [])
}
