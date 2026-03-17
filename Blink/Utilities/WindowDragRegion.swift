import SwiftUI
import AppKit

/// A background region that lets empty chrome areas drag the window
/// without making the whole content area draggable.
struct WindowDragRegion: NSViewRepresentable {

    func makeNSView(context: Context) -> DragRegionView {
        DragRegionView()
    }

    func updateNSView(_ nsView: DragRegionView, context: Context) {}

    final class DragRegionView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
