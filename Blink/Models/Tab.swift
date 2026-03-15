import Foundation

struct AppTab: Identifiable, Equatable, Hashable {
    let id: String
    let type: String
    var label: String
    let projectId: String
}
