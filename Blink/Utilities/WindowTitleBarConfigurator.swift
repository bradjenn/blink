import SwiftUI
import AppKit

/// Hides the traffic light buttons that .windowStyle(.hiddenTitleBar) leaves behind.
/// Also intercepts window-close requests so Blink can close the active workspace
/// window rather than the macOS app window itself.
struct WindowTitleBarConfigurator: NSViewRepresentable {
    let onCloseRequest: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCloseRequest: onCloseRequest)
    }

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.configureHandler = { window in
            Self.apply(to: window)
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowObserverView, context: Context) {
        context.coordinator.onCloseRequest = onCloseRequest
        if let window = nsView.window {
            Self.apply(to: window)
            context.coordinator.attach(to: window)
        }
    }

    private static func apply(to window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier("BlinkMainWorkspaceWindow")
        window.styleMask.insert(.fullSizeContentView)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isMovableByWindowBackground = false
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var onCloseRequest: () -> Void
        weak var window: NSWindow?

        init(onCloseRequest: @escaping () -> Void) {
            self.onCloseRequest = onCloseRequest
        }

        func attach(to window: NSWindow) {
            guard self.window !== window else { return }
            self.window = window
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            onCloseRequest()
            return false
        }
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
