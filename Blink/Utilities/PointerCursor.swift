import SwiftUI
import AppKit

/// Sets the cursor to a pointing hand when hovering over this view.
/// Uses NSView.addCursorRect which is more reliable than NSCursor.push/pop
/// in scroll views and lazy stacks.
struct PointerCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = PointerCursorNSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class PointerCursorNSView: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

extension View {
    /// Adds a pointing hand cursor when hovering over this view.
    func pointerCursor() -> some View {
        overlay(PointerCursorView())
    }
}
