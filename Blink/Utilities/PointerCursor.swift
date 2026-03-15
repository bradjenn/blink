import SwiftUI
import AppKit

extension View {
    /// Adds a pointing hand cursor when hovering over this view.
    func pointerCursor() -> some View {
        self.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}
