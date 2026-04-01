import SwiftUI

@main
enum BlinkEntry {
    static func main() {
        if shouldStartChromiumRuntime,
           BlinkChromiumRuntime.canStartInCurrentBundle() {
            BlinkChromiumRuntime.prepareApplicationIfNeeded()
            _ = BlinkChromiumRuntime.shared().startIfNeeded()
        }

        BApp.main()
    }

    private static var shouldStartChromiumRuntime: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }
}
