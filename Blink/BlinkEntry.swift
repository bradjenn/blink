import SwiftUI

@main
enum BlinkEntry {
    static func main() {
        if BlinkChromiumRuntime.canStartInCurrentBundle() {
            BlinkChromiumRuntime.prepareApplicationIfNeeded()
            _ = BlinkChromiumRuntime.shared().startIfNeeded()
        }

        BApp.main()
    }
}
