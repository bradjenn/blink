import XCTest
import AppKit
@testable import Blink

@MainActor
final class TerminalSurfaceViewTests: XCTestCase {
    func testSetFrameSizeResizesAndRedrawsSurface() {
        let view = makeSurfaceView()
        let sink = RecordingSurfaceCommandSink()
        view.commandSinkOverride = sink

        view.setFrameSize(NSSize(width: 480, height: 320))

        assertResizeAndRedrawCalls(on: view, sink: sink)
    }

    func testSetBoundsSizeResizesAndRedrawsSurface() {
        let view = makeSurfaceView()
        let sink = RecordingSurfaceCommandSink()
        view.commandSinkOverride = sink

        view.setBoundsSize(NSSize(width: 360, height: 240))

        assertResizeAndRedrawCalls(on: view, sink: sink)
    }

    private func makeSurfaceView() -> TerminalSurfaceView {
        let view = TerminalSurfaceView(
            app: GhosttyApp(),
            tabId: "test-tab",
            workingDirectory: "/tmp"
        )
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        return view
    }

    private func assertResizeAndRedrawCalls(
        on view: TerminalSurfaceView,
        sink: RecordingSurfaceCommandSink
    ) {
        let backingSize = view.convertToBacking(view.bounds.size)
        XCTAssertEqual(
            sink.calls,
            [
                .setSize(width: UInt32(backingSize.width), height: UInt32(backingSize.height)),
                .refresh,
                .draw,
            ]
        )
    }
}

private final class RecordingSurfaceCommandSink: TerminalSurfaceCommandSink {
    enum Call: Equatable {
        case setContentScale(x: Double, y: Double)
        case setSize(width: UInt32, height: UInt32)
        case refresh
        case draw
    }

    private(set) var calls: [Call] = []

    func setContentScale(x: Double, y: Double) {
        calls.append(.setContentScale(x: x, y: y))
    }

    func setSize(width: UInt32, height: UInt32) {
        calls.append(.setSize(width: width, height: height))
    }

    func refresh() {
        calls.append(.refresh)
    }

    func draw() {
        calls.append(.draw)
    }
}
