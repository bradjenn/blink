import Foundation
import Observation

@MainActor
@Observable
final class BrowserSessionModel {
    var state: BrowserTabState
    var addressBarFocusRequestID: Int

    init(
        state: BrowserTabState,
        addressBarFocusRequestID: Int = 0
    ) {
        self.state = state
        self.addressBarFocusRequestID = addressBarFocusRequestID
    }
}
