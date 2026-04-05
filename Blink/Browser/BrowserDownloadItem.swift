import Foundation

struct BrowserDownloadItem: Identifiable, Equatable, Codable {
    let id: String
    let browserTabId: String
    let projectId: String
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
