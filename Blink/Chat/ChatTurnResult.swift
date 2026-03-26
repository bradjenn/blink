import Foundation

struct ChatTurnWorkItem: Equatable, Hashable {
    let id: String
    let kind: ChatWorkItemKind
    let title: String
    let detail: String?
    let output: String?
    let status: ChatWorkItemStatus
    let exitCode: Int?
}

struct ChatTurnResult {
    let sessionId: String
    let text: String
    let runtimeEvents: [ChatTurnRuntimeEvent]

    var workItems: [ChatTurnWorkItem] {
        runtimeEvents.compactMap(\.workItem)
    }

    init(
        sessionId: String,
        text: String,
        runtimeEvents: [ChatTurnRuntimeEvent] = [],
        workItems: [ChatTurnWorkItem] = []
    ) {
        self.sessionId = sessionId
        self.text = text
        if runtimeEvents.isEmpty, !workItems.isEmpty {
            self.runtimeEvents = workItems.map { item in
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

                return ChatTurnRuntimeEvent(
                    id: item.id,
                    kind: kind,
                    title: item.title,
                    detail: item.detail,
                    output: item.output,
                    status: status,
                    exitCode: item.exitCode,
                    requestId: nil,
                    questions: [],
                    changedFiles: []
                )
            }
        } else {
            self.runtimeEvents = runtimeEvents
        }
    }
}
