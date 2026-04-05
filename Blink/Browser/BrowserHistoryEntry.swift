import Foundation

struct BrowserHistoryEntry: Codable, Equatable, Hashable, Identifiable {
    var urlString: String
    var title: String?
    var lastVisitedAt: Date

    var id: String { urlString }

    var host: String? {
        guard let url = URL(string: urlString),
              let host = url.host(percentEncoded: false),
              !host.isEmpty else {
            return nil
        }

        return host
    }

    var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }

        return host ?? urlString
    }

    var isLocal: Bool {
        BrowserURLResolver.isLocalURLString(urlString)
    }
}
