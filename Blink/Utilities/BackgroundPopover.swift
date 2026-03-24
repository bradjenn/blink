import SwiftUI

enum BackgroundPopoverPlacement {
    case belowLeading
    case aboveLeading
}

/// A dropdown modifier that shows a borderless panel anchored at the
/// bottom-leading edge of the source view. No arrow, no centering.
struct BackgroundPopoverModifier<PopoverContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let placement: BackgroundPopoverPlacement
    @ViewBuilder let popoverContent: () -> PopoverContent

    func body(content: Content) -> some View {
        content
            .background(
                BackgroundPopoverAnchor(
                    isPresented: $isPresented,
                    placement: placement,
                    popoverContent: popoverContent
                )
            )
    }
}

private struct BackgroundPopoverAnchor<PopoverContent: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let placement: BackgroundPopoverPlacement
    @ViewBuilder let popoverContent: () -> PopoverContent

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            if context.coordinator.panel == nil {
                let hostingView = NSHostingView(rootView: popoverContent())
                let fittingSize = hostingView.fittingSize

                let panel = NSPanel(
                    contentRect: NSRect(origin: .zero, size: fittingSize),
                    styleMask: [.nonactivatingPanel],
                    backing: .buffered,
                    defer: true
                )
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.level = .popUpMenu
                panel.contentView = hostingView

                context.coordinator.panel = panel
                context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown]
                ) { event in
                    if let panel = context.coordinator.panel,
                       !panel.frame.contains(NSEvent.mouseLocation) {
                        self.isPresented = false
                    }
                    return event
                }

                DispatchQueue.main.async {
                    guard let window = nsView.window else { return }
                    let viewFrame = nsView.convert(nsView.bounds, to: nil)
                    let panelOrigin: NSPoint

                    switch placement {
                    case .belowLeading:
                        let screenPoint = window.convertPoint(toScreen: NSPoint(
                            x: viewFrame.minX,
                            y: viewFrame.minY
                        ))
                        panelOrigin = NSPoint(
                            x: screenPoint.x + 3,
                            y: screenPoint.y - 2
                        )
                    case .aboveLeading:
                        let screenPoint = window.convertPoint(toScreen: NSPoint(
                            x: viewFrame.minX,
                            y: viewFrame.maxY
                        ))
                        panelOrigin = NSPoint(
                            x: screenPoint.x + 3,
                            y: screenPoint.y + fittingSize.height + 2
                        )
                    }

                    panel.setFrameTopLeftPoint(panelOrigin)
                    window.addChildWindow(panel, ordered: .above)
                }
            }
        } else {
            context.coordinator.cleanup()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    class Coordinator {
        var panel: NSPanel?
        var monitor: Any?
        @Binding var isPresented: Bool

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func cleanup() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            panel?.orderOut(nil)
            panel?.parent?.removeChildWindow(panel!)
            panel = nil
        }

        deinit {
            cleanup()
        }
    }
}

extension View {
    func backgroundPopover<Content: View>(
        isPresented: Binding<Bool>,
        placement: BackgroundPopoverPlacement = .belowLeading,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(
            BackgroundPopoverModifier(
                isPresented: isPresented,
                placement: placement,
                popoverContent: content
            )
        )
    }
}
