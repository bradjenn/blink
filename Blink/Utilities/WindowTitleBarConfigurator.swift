import SwiftUI
import AppKit

/// Hides the traffic light buttons that .windowStyle(.hiddenTitleBar) leaves behind.
struct WindowTitleBarConfigurator: NSViewRepresentable {

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.configureHandler = { window in
            Self.apply(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowObserverView, context: Context) {
        if let window = nsView.window {
            Self.apply(to: window)
        }
    }

    private static func apply(to window: NSWindow) {
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isMovableByWindowBackground = false
    }

    final class WindowObserverView: NSView {
        var configureHandler: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            configureHandler?(window)
        }
    }
}
