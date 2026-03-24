import Foundation

struct ChatStoreSnapshot: Codable {
    var threads: [ChatThread]
    var messages: [ChatMessage]

    static let empty = ChatStoreSnapshot(threads: [], messages: [])
}
