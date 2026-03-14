import SwiftUI

@main
struct BApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Blink")
                .frame(minWidth: 800, minHeight: 500)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1200, height: 750)
    }
}
