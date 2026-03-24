import Foundation

enum ChatProviderError: LocalizedError {
    case invalidRequest(String)
    case launchFailed(String)
    case executionFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let message),
             .launchFailed(let message),
             .executionFailed(let message),
             .invalidResponse(let message):
            return message
        }
    }
}
