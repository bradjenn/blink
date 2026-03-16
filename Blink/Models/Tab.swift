import Foundation

struct AppTab: Identifiable, Equatable, Hashable {
    let id: String
    let type: String
    var label: String
    var defaultLabel: String
    let projectId: String
    var command: String? = nil
}
