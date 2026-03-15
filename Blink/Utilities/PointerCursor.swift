import SwiftUI
import AppKit

/// Reliable pointer cursor using NSTrackingArea in a background NSView.
/// The background position means it doesn't intercept hit testing or hover events.
struct PointerCursorRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> PointerTrackingView {
        PointerTrackingView()
    }

    func updateNSView(_ nsView: PointerTrackingView, context: Context) {}
}

class PointerTrackingView: NSView {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

extension View {
    /// Adds a pointing hand cursor when hovering. Uses a background NSView
    /// with NSTrackingArea so it doesn't interfere with SwiftUI onHover.
    func pointerCursor() -> some View {
        self.background(PointerCursorRepresentable())
    }
}
