import SwiftUI
import AppKit

extension View {
    /// Adds a pointing hand cursor when hovering.
    /// Uses set() which is stateless — no push/pop stack to get unbalanced
    /// when adjacent elements fire overlapping enter/exit events.
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
