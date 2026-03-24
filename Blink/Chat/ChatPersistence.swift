import Foundation

actor ChatPersistence {
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        self.fileURL = appSupportURL
            .appendingPathComponent("Blink", isDirectory: true)
            .appendingPathComponent("chat-store.json", isDirectory: false)
    }

    func load() throws -> ChatStoreSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.chatStore.decode(ChatStoreSnapshot.self, from: data)
    }

    func save(_ snapshot: ChatStoreSnapshot) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try JSONEncoder.chatStore.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}

private extension JSONDecoder {
    static let chatStore: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension JSONEncoder {
    static let chatStore: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
