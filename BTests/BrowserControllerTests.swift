import XCTest
@testable import Blink

@MainActor
final class BrowserControllerTests: XCTestCase {
    func testFocusWebViewDoesNotRepublishWhenAlreadyFocused() {
        var publishedStates: [BrowserTabState] = []
        let controller = BrowserController(
            tabId: "browser-tab",
            initialState: BrowserTabState(preferredFocus: .webView)
        ) { state in
            publishedStates.append(state)
        }

        controller.focusWebView()

        XCTAssertTrue(publishedStates.isEmpty)
    }

    func testFocusAddressBarDoesNotRepublishWhenAlreadyFocused() {
        var publishedStates: [BrowserTabState] = []
        let controller = BrowserController(
            tabId: "browser-tab",
            initialState: BrowserTabState(preferredFocus: .addressBar)
        ) { state in
            publishedStates.append(state)
        }

        controller.focusAddressBar()

        XCTAssertTrue(publishedStates.isEmpty)
    }

    func testFocusWebViewPublishesWhenFocusTargetChanges() {
        var publishedStates: [BrowserTabState] = []
        let controller = BrowserController(
            tabId: "browser-tab",
            initialState: BrowserTabState(preferredFocus: .addressBar)
        ) { state in
            publishedStates.append(state)
        }

        controller.focusWebView()

        XCTAssertEqual(publishedStates.count, 1)
        XCTAssertEqual(publishedStates.first?.preferredFocus, .webView)
    }

    func testSwipeTrackerNavigatesBackAfterCrossingThreshold() {
        var tracker = BrowserSwipeNavigationTracker()

        let first = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 36,
                scrollingDeltaY: 4,
                hasPreciseScrollingDeltas: true,
                phase: [.began],
                momentumPhase: [],
                timestamp: 1
            )
        ) { _ in true }
        let second = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 40,
                scrollingDeltaY: 3,
                hasPreciseScrollingDeltas: true,
                phase: [.changed],
                momentumPhase: [],
                timestamp: 1.1
            )
        ) { _ in true }
        let ended = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 0,
                scrollingDeltaY: 0,
                hasPreciseScrollingDeltas: true,
                phase: [.ended],
                momentumPhase: [],
                timestamp: 1.2
            )
        ) { _ in true }

        XCTAssertEqual(first.outcome, .consumed)
        XCTAssertEqual(first.feedback?.direction, .previous)
        XCTAssertEqual(first.feedback?.isArmed, false)
        XCTAssertEqual(first.feedback?.isCommitted, false)
        XCTAssertEqual(second.outcome, .consumed)
        XCTAssertEqual(second.feedback?.direction, .previous)
        XCTAssertEqual(second.feedback?.progress, 1)
        XCTAssertEqual(second.feedback?.isArmed, true)
        XCTAssertEqual(second.feedback?.isCommitted, false)
        XCTAssertEqual(ended.outcome, .navigate(.previous))
        XCTAssertEqual(ended.feedback?.isArmed, true)
        XCTAssertEqual(ended.feedback?.isCommitted, true)
    }

    func testSwipeTrackerIgnoresUnavailableNavigation() {
        var tracker = BrowserSwipeNavigationTracker()

        let outcome = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 80,
                scrollingDeltaY: 2,
                hasPreciseScrollingDeltas: true,
                phase: [.began],
                momentumPhase: [],
                timestamp: 1
            )
        ) { _ in false }

        XCTAssertEqual(outcome.outcome, .ignored)
        XCTAssertNil(outcome.feedback)
    }

    func testSwipeTrackerRetreatsWhenGestureMovesBackBeforeArming() {
        var tracker = BrowserSwipeNavigationTracker()

        let first = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 40,
                scrollingDeltaY: 2,
                hasPreciseScrollingDeltas: true,
                phase: [.began],
                momentumPhase: [],
                timestamp: 1
            )
        ) { _ in true }
        let second = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: -40,
                scrollingDeltaY: 2,
                hasPreciseScrollingDeltas: true,
                phase: [.changed],
                momentumPhase: [],
                timestamp: 1.1
            )
        ) { _ in true }
        let third = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 80,
                scrollingDeltaY: 2,
                hasPreciseScrollingDeltas: true,
                phase: [.changed],
                momentumPhase: [],
                timestamp: 1.2
            )
        ) { _ in true }
        let ended = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 0,
                scrollingDeltaY: 0,
                hasPreciseScrollingDeltas: true,
                phase: [.ended],
                momentumPhase: [],
                timestamp: 1.3
            )
        ) { _ in true }

        XCTAssertEqual(first.outcome, .consumed)
        XCTAssertEqual(first.feedback?.direction, .previous)
        XCTAssertGreaterThan(first.feedback?.progress ?? 0, 0.5)
        XCTAssertEqual(second.outcome, .consumed)
        XCTAssertNil(second.feedback)
        XCTAssertEqual(third.outcome, .consumed)
        XCTAssertEqual(third.feedback?.isArmed, true)
        XCTAssertEqual(ended.outcome, .navigate(.previous))
    }

    func testSwipeTrackerRetreatsAfterArmingWhenGestureReverses() {
        var tracker = BrowserSwipeNavigationTracker()

        _ = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 40,
                scrollingDeltaY: 2,
                hasPreciseScrollingDeltas: true,
                phase: [.began],
                momentumPhase: [],
                timestamp: 1
            )
        ) { _ in true }

        let armed = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 40,
                scrollingDeltaY: 2,
                hasPreciseScrollingDeltas: true,
                phase: [.changed],
                momentumPhase: [],
                timestamp: 1.1
            )
        ) { _ in true }

        let continued = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: -18,
                scrollingDeltaY: 1,
                hasPreciseScrollingDeltas: true,
                phase: [.changed],
                momentumPhase: [],
                timestamp: 1.2
            )
        ) { _ in true }

        let ended = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 0,
                scrollingDeltaY: 0,
                hasPreciseScrollingDeltas: true,
                phase: [.ended],
                momentumPhase: [],
                timestamp: 1.3
            )
        ) { _ in true }

        XCTAssertEqual(armed.feedback?.direction, .previous)
        XCTAssertEqual(armed.feedback?.isArmed, true)
        XCTAssertEqual(continued.feedback?.direction, .previous)
        XCTAssertLessThan(continued.feedback?.progress ?? 1, 1)
        XCTAssertEqual(continued.feedback?.isArmed, false)
        XCTAssertEqual(ended.outcome, .consumed)
    }

    func testSwipeTrackerCanReverseDirectionWithinSingleGesture() {
        var tracker = BrowserSwipeNavigationTracker()

        let began = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 44,
                scrollingDeltaY: 2,
                hasPreciseScrollingDeltas: true,
                phase: [.began],
                momentumPhase: [],
                timestamp: 1
            )
        ) { _ in true }

        let armedBack = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 36,
                scrollingDeltaY: 2,
                hasPreciseScrollingDeltas: true,
                phase: [.changed],
                momentumPhase: [],
                timestamp: 1.1
            )
        ) { _ in true }

        let crossedNeutral = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: -120,
                scrollingDeltaY: 3,
                hasPreciseScrollingDeltas: true,
                phase: [.changed],
                momentumPhase: [],
                timestamp: 1.2
            )
        ) { _ in true }

        let armedForward = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: -48,
                scrollingDeltaY: 2,
                hasPreciseScrollingDeltas: true,
                phase: [.changed],
                momentumPhase: [],
                timestamp: 1.3
            )
        ) { _ in true }

        let ended = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 0,
                scrollingDeltaY: 0,
                hasPreciseScrollingDeltas: true,
                phase: [.ended],
                momentumPhase: [],
                timestamp: 1.4
            )
        ) { _ in true }

        XCTAssertEqual(began.feedback?.direction, .previous)
        XCTAssertEqual(armedBack.feedback?.isArmed, true)
        XCTAssertEqual(crossedNeutral.feedback?.direction, .next)
        XCTAssertEqual(crossedNeutral.feedback?.isArmed, false)
        XCTAssertGreaterThan(crossedNeutral.feedback?.progress ?? 0, 0)
        XCTAssertEqual(armedForward.feedback?.direction, .next)
        XCTAssertEqual(armedForward.feedback?.isArmed, true)
        XCTAssertEqual(ended.outcome, .navigate(.next))
    }

    func testSwipeTrackerNavigatesWhenGestureStaysArmedUntilRelease() {
        var tracker = BrowserSwipeNavigationTracker()

        _ = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 40,
                scrollingDeltaY: 2,
                hasPreciseScrollingDeltas: true,
                phase: [.began],
                momentumPhase: [],
                timestamp: 1
            )
        ) { _ in true }

        let armed = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 40,
                scrollingDeltaY: 2,
                hasPreciseScrollingDeltas: true,
                phase: [.changed],
                momentumPhase: [],
                timestamp: 1.1
            )
        ) { _ in true }

        let ended = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 0,
                scrollingDeltaY: 0,
                hasPreciseScrollingDeltas: true,
                phase: [.ended],
                momentumPhase: [],
                timestamp: 1.2
            )
        ) { _ in true }

        XCTAssertEqual(armed.feedback?.direction, .previous)
        XCTAssertEqual(armed.feedback?.isArmed, true)
        XCTAssertEqual(ended.outcome, .navigate(.previous))
    }

    func testSwipeTrackerKeepsActiveGestureAcrossNoisyMidGestureEvent() {
        var tracker = BrowserSwipeNavigationTracker()

        let began = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 28,
                scrollingDeltaY: 4,
                hasPreciseScrollingDeltas: true,
                phase: [.began],
                momentumPhase: [],
                timestamp: 1
            )
        ) { _ in true }

        let noisy = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 2,
                scrollingDeltaY: 5,
                hasPreciseScrollingDeltas: true,
                phase: [.changed],
                momentumPhase: [],
                timestamp: 1.1
            )
        ) { _ in true }

        let continued = tracker.handle(
            BrowserSwipeNavigationEvent(
                scrollingDeltaX: 28,
                scrollingDeltaY: 3,
                hasPreciseScrollingDeltas: true,
                phase: [.changed],
                momentumPhase: [],
                timestamp: 1.2
            )
        ) { _ in true }

        XCTAssertEqual(began.outcome, .consumed)
        XCTAssertEqual(began.feedback?.direction, .previous)
        XCTAssertEqual(noisy.outcome, .consumed)
        XCTAssertEqual(noisy.feedback?.direction, .previous)
        XCTAssertGreaterThan(noisy.feedback?.progress ?? 0, 0)
        XCTAssertEqual(continued.outcome, .consumed)
        XCTAssertEqual(continued.feedback?.direction, .previous)
    }
}
