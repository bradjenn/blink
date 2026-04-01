import XCTest
import AppKit
@testable import Blink

@MainActor
final class TerminalSurfaceViewTests: XCTestCase {
    func testSubmittedLineBufferUsesCorrectedText() {
        var buffer = TerminalSubmittedLineBuffer()

        _ = buffer.insert("helo")
        buffer.handleKeyCode(51)
        _ = buffer.insert("lo")

        XCTAssertEqual(buffer.submit(), "hello")
    }

    func testSubmittedLineBufferSupportsCursorEdits() {
        var buffer = TerminalSubmittedLineBuffer()

        _ = buffer.insert("hllo")
        buffer.handleKeyCode(123)
        buffer.handleKeyCode(123)
        buffer.handleKeyCode(123)
        _ = buffer.insert("e")

        XCTAssertEqual(buffer.submit(), "hello")
    }

    func testSetFrameSizeResizesSurfaceWithoutForcingRefresh() {
        let view = makeSurfaceView()
        let sink = RecordingSurfaceCommandSink()
        view.commandSinkOverride = sink

        view.setFrameSize(NSSize(width: 480, height: 320))

        assertResizeCalls(on: view, sink: sink)
    }

    func testSetBoundsSizeResizesSurfaceWithoutForcingRefresh() {
        let view = makeSurfaceView()
        let sink = RecordingSurfaceCommandSink()
        view.commandSinkOverride = sink

        view.setBoundsSize(NSSize(width: 360, height: 240))

        assertResizeCalls(on: view, sink: sink)
    }

    func testRepeatedResizeWithSameBackingSizeDoesNotResendCommands() {
        let view = makeSurfaceView()
        let sink = RecordingSurfaceCommandSink()
        view.commandSinkOverride = sink

        view.setFrameSize(NSSize(width: 480, height: 320))
        sink.calls.removeAll()

        view.layout()

        XCTAssertTrue(sink.calls.isEmpty)
    }

    private func makeSurfaceView() -> TerminalSurfaceView {
        let view = TerminalSurfaceView(
            app: GhosttyApp(),
            tabId: "test-tab",
            paneId: "pane-test",
            projectId: "test-project",
            projectName: "Test Project",
            workingDirectory: "/tmp"
        )
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        return view
    }

    private func assertResizeCalls(
        on view: TerminalSurfaceView,
        sink: RecordingSurfaceCommandSink
    ) {
        let logicalSize = view.bounds.size
        let rawBackingSize = view.convertToBacking(NSRect(origin: .zero, size: logicalSize)).size
        let backingSize = CGSize(
            width: floor(max(0, rawBackingSize.width)),
            height: floor(max(0, rawBackingSize.height))
        )
        XCTAssertEqual(
            sink.calls,
            [
                .setContentScale(x: backingSize.width / logicalSize.width, y: backingSize.height / logicalSize.height),
                .setSize(width: UInt32(backingSize.width), height: UInt32(backingSize.height)),
            ]
        )
    }
}

private final class RecordingSurfaceCommandSink: TerminalSurfaceCommandSink {
    enum Call: Equatable {
        case setContentScale(x: Double, y: Double)
        case setSize(width: UInt32, height: UInt32)
    }

    var calls: [Call] = []

    func setContentScale(x: Double, y: Double) {
        calls.append(.setContentScale(x: x, y: y))
    }

    func setSize(width: UInt32, height: UInt32) {
        calls.append(.setSize(width: width, height: height))
    }
}
