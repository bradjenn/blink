import Foundation

struct BrowserDownloadItem: Identifiable, Equatable, Codable {
    let id: String
    let browserTabId: String
    let workspaceId: String
    var sourceURLString: String?
    var suggestedFileName: String
    var destinationPath: String?
    var receivedBytes: Int64
    var totalBytes: Int64
    var percentComplete: Int
    var currentSpeed: Int64
    var isInProgress: Bool
    var isComplete: Bool
    var isCanceled: Bool
    var isInterrupted: Bool
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case browserTabId
        case workspaceId
        case projectId
        case sourceURLString
        case suggestedFileName
        case destinationPath
        case receivedBytes
        case totalBytes
        case percentComplete
        case currentSpeed
        case isInProgress
        case isComplete
        case isCanceled
        case isInterrupted
        case updatedAt
    }

    init(
        id: String,
        browserTabId: String,
        workspaceId: String,
        sourceURLString: String?,
        suggestedFileName: String,
        destinationPath: String?,
        receivedBytes: Int64,
        totalBytes: Int64,
        percentComplete: Int,
        currentSpeed: Int64,
        isInProgress: Bool,
        isComplete: Bool,
        isCanceled: Bool,
        isInterrupted: Bool,
        updatedAt: Date
    ) {
        self.id = id
        self.browserTabId = browserTabId
        self.workspaceId = workspaceId
        self.sourceURLString = sourceURLString
        self.suggestedFileName = suggestedFileName
        self.destinationPath = destinationPath
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.percentComplete = percentComplete
        self.currentSpeed = currentSpeed
        self.isInProgress = isInProgress
        self.isComplete = isComplete
        self.isCanceled = isCanceled
        self.isInterrupted = isInterrupted
        self.updatedAt = updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        browserTabId = try container.decode(String.self, forKey: .browserTabId)
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
            ?? container.decode(String.self, forKey: .projectId)
        sourceURLString = try container.decodeIfPresent(String.self, forKey: .sourceURLString)
        suggestedFileName = try container.decode(String.self, forKey: .suggestedFileName)
        destinationPath = try container.decodeIfPresent(String.self, forKey: .destinationPath)
        receivedBytes = try container.decode(Int64.self, forKey: .receivedBytes)
        totalBytes = try container.decode(Int64.self, forKey: .totalBytes)
        percentComplete = try container.decode(Int.self, forKey: .percentComplete)
        currentSpeed = try container.decode(Int64.self, forKey: .currentSpeed)
        isInProgress = try container.decode(Bool.self, forKey: .isInProgress)
        isComplete = try container.decode(Bool.self, forKey: .isComplete)
        isCanceled = try container.decode(Bool.self, forKey: .isCanceled)
        isInterrupted = try container.decode(Bool.self, forKey: .isInterrupted)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(browserTabId, forKey: .browserTabId)
        try container.encode(workspaceId, forKey: .workspaceId)
        try container.encodeIfPresent(sourceURLString, forKey: .sourceURLString)
        try container.encode(suggestedFileName, forKey: .suggestedFileName)
        try container.encodeIfPresent(destinationPath, forKey: .destinationPath)
        try container.encode(receivedBytes, forKey: .receivedBytes)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(percentComplete, forKey: .percentComplete)
        try container.encode(currentSpeed, forKey: .currentSpeed)
        try container.encode(isInProgress, forKey: .isInProgress)
        try container.encode(isComplete, forKey: .isComplete)
        try container.encode(isCanceled, forKey: .isCanceled)
        try container.encode(isInterrupted, forKey: .isInterrupted)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var fileName: String {
        if let destinationPath {
            let candidate = URL(fileURLWithPath: destinationPath).lastPathComponent
            if !candidate.isEmpty {
                return candidate
            }
        }

        let trimmed = suggestedFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "download" : trimmed
    }

    var destinationURL: URL? {
        guard let destinationPath, !destinationPath.isEmpty else { return nil }
        return URL(fileURLWithPath: destinationPath)
    }

    var progressFraction: Double? {
        guard totalBytes > 0 else { return nil }
        return min(max(Double(receivedBytes) / Double(totalBytes), 0), 1)
    }

    var statusText: String {
        if isComplete {
            return "Completed"
        }

        if isCanceled {
            return "Canceled"
        }

        if isInterrupted {
            return "Interrupted"
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        if totalBytes > 0 {
            return "\(formatter.string(fromByteCount: receivedBytes)) of \(formatter.string(fromByteCount: totalBytes))"
        }

        if receivedBytes > 0 {
            return formatter.string(fromByteCount: receivedBytes)
        }

        return "Starting..."
    }
}
