import Foundation

enum ChatMessageRole: String, Codable, CaseIterable {
    case user
    case assistant
    case system
}

enum ChatMessageLayoutHint: String, Codable {
    case comparison
}

enum ChatWorkItemKind: String, Codable, Hashable {
    case commandExecution
    case reasoning
    case plan
}

enum ChatWorkItemStatus: String, Codable, Hashable {
    case inProgress
    case completed
    case failed
}

struct ChatMessage: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let threadId: String
    let role: ChatMessageRole
    let content: String
    let attachments: [ChatAttachment]
    let participant: String?
    let turnId: String?
    let layoutHint: ChatMessageLayoutHint?
    let createdAt: Date

    init(
        id: String,
        threadId: String,
        role: ChatMessageRole,
        content: String,
        attachments: [ChatAttachment] = [],
        participant: String? = nil,
        turnId: String? = nil,
        layoutHint: ChatMessageLayoutHint? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.threadId = threadId
        self.role = role
        self.content = content
        self.attachments = attachments
        self.participant = participant
        self.turnId = turnId
        self.layoutHint = layoutHint
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case threadId
        case role
        case content
        case attachments
        case participant
        case turnId
        case layoutHint
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        threadId = try container.decode(String.self, forKey: .threadId)
        role = try container.decode(ChatMessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        participant = try container.decodeIfPresent(String.self, forKey: .participant)
        turnId = try container.decodeIfPresent(String.self, forKey: .turnId)
        layoutHint = try container.decodeIfPresent(ChatMessageLayoutHint.self, forKey: .layoutHint)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(threadId, forKey: .threadId)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(attachments, forKey: .attachments)
        try container.encodeIfPresent(participant, forKey: .participant)
        try container.encodeIfPresent(turnId, forKey: .turnId)
        try container.encodeIfPresent(layoutHint, forKey: .layoutHint)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct ChatMessageWorkItem: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let threadId: String
    let messageId: String
    let kind: ChatWorkItemKind
    let title: String
    let detail: String?
    let output: String?
    let status: ChatWorkItemStatus
    let exitCode: Int?
    let createdAt: Date
}
