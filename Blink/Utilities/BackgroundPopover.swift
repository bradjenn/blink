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
    private var animationDuration: TimeInterval { 0.18 }
    private var travelDistance: CGFloat { 12 }

    @Binding var isPresented: Bool
    let placement: BackgroundPopoverPlacement
    @ViewBuilder let popoverContent: () -> PopoverContent

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            context.coordinator.cancelPendingDismissal()

            if context.coordinator.panel == nil {
                let hostingView = NSHostingView(
                    rootView: AnyView(
                        AnimatedBackgroundPopoverContent(
                            placement: placement,
                            travelDistance: travelDistance,
                            animationDuration: animationDuration,
                            content: popoverContent
                        )
                    )
                )
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
                panel.alphaValue = 0
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
                    guard let window = nsView.window,
                          let panel = context.coordinator.panel else { return }
                    let viewFrame = nsView.convert(nsView.bounds, to: nil)
                    let panelTopLeft: NSPoint

                    switch placement {
                    case .belowLeading:
                        let screenPoint = window.convertPoint(toScreen: NSPoint(
                            x: viewFrame.minX,
                            y: viewFrame.minY
                        ))
                        panelTopLeft = NSPoint(
                            x: screenPoint.x + 3,
                            y: screenPoint.y - 2
                        )
                    case .aboveLeading:
                        let screenPoint = window.convertPoint(toScreen: NSPoint(
                            x: viewFrame.minX,
                            y: viewFrame.maxY
                        ))
                        panelTopLeft = NSPoint(
                            x: screenPoint.x + 3,
                            y: screenPoint.y + fittingSize.height + 2
                        )
                    }

                    let visibleFrameOrigin = frameOrigin(forTopLeftPoint: panelTopLeft, size: fittingSize)
                    window.addChildWindow(panel, ordered: .above)
                    panel.setFrameOrigin(visibleFrameOrigin)
                    panel.orderFront(nil)

                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = animationDuration
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        panel.animator().alphaValue = 1
                    }
                }
            }
        } else {
            context.coordinator.dismiss(animationDuration: animationDuration)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    private func frameOrigin(forTopLeftPoint point: NSPoint, size: CGSize) -> NSPoint {
        NSPoint(x: point.x, y: point.y - size.height)
    }

    class Coordinator {
        var panel: NSPanel?
        var monitor: Any?
        private var isDismissing = false
        @Binding var isPresented: Bool

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func cancelPendingDismissal() {
            guard isDismissing, let panel else { return }

            isDismissing = false
            panel.alphaValue = 1
        }

        func dismiss(animationDuration: TimeInterval) {
            guard let panel else {
                cleanup()
                return
            }

            guard !isDismissing else { return }
            isDismissing = true

            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                guard let self else { return }
                guard !self.isPresented else {
                    self.isDismissing = false
                    panel.alphaValue = 1
                    return
                }

                self.cleanup()
            }
        }

        func cleanup() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            panel?.orderOut(nil)
            panel?.parent?.removeChildWindow(panel!)
            panel = nil
            isDismissing = false
        }

        deinit {
            cleanup()
        }
    }
}

private struct AnimatedBackgroundPopoverContent<Content: View>: View {
    let placement: BackgroundPopoverPlacement
    let travelDistance: CGFloat
    let animationDuration: TimeInterval
    @ViewBuilder let content: () -> Content

    @State private var isVisible = false

    var body: some View {
        content()
            .offset(y: isVisible ? 0 : initialYOffset)
            .scaleEffect(isVisible ? 1 : 0.985, anchor: anchor)
            .onAppear {
                guard !isVisible else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: animationDuration)) {
                        isVisible = true
                    }
                }
            }
    }

    private var initialYOffset: CGFloat {
        switch placement {
        case .belowLeading:
            -travelDistance
        case .aboveLeading:
            travelDistance
        }
    }

    private var anchor: UnitPoint {
        switch placement {
        case .belowLeading:
            .topLeading
        case .aboveLeading:
            .bottomLeading
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
