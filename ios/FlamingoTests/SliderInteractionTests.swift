import XCTest
@testable import Flamingo

@MainActor final class SliderInteractionTests: XCTestCase {
    func testContinuousPreviewDoesNotSeekUntilRelease() {
        let control = AdaptiveScrubberControl()
        control.total = 100; control.isEnabled = true
        var previews: [Double] = [], commits: [Double] = []
        control.preview = { previews.append($0) }
        control.commit = { commits.append($0) }
        XCTAssertTrue(control.startInteraction(at: 0.2))
        for fraction in [0.25, 0.5, 0.75] { XCTAssertTrue(control.moveInteraction(to: fraction)) }
        XCTAssertEqual(previews.last, 75)
        XCTAssertTrue(commits.isEmpty)
        control.finishInteraction(at: 0.8)
        control.finishInteraction(at: 0.8)
        XCTAssertEqual(commits, [80])
        control.invalidateInteraction(notify: false)
    }

    func testCancellationNeverCommitsAndNextTouchWorks() {
        let control = AdaptiveScrubberControl()
        control.total = 100; control.isEnabled = true
        var commits: [Double] = [], cancellations = 0
        control.commit = { commits.append($0) }
        control.cancelled = { cancellations += 1 }
        control.startInteraction(at: 0.4)
        XCTAssertFalse(control.startInteraction(at: 0.8), "A second touch cannot replace a tracked interaction")
        control.cancelTracking(with: nil)
        control.finishInteraction(at: 0.9)
        XCTAssertEqual(cancellations, 1)
        XCTAssertTrue(commits.isEmpty)
        XCTAssertTrue(control.startInteraction(at: 0.1))
        control.finishInteraction(at: 0.3)
        XCTAssertEqual(commits, [30])
        control.invalidateInteraction(notify: false)
        XCTAssertEqual(control.phase, .idle)
    }

    func testContextInvalidationRejectsOldReleaseAndClampsOutsideTrack() {
        let control = AdaptiveScrubberControl()
        control.total = 100; control.isEnabled = true
        var commits: [Double] = []
        control.commit = { commits.append($0) }
        control.startInteraction(at: 0.5)
        control.invalidateInteraction(notify: false)
        control.finishInteraction(at: 0.8)
        XCTAssertTrue(commits.isEmpty)
        control.startInteraction(at: -0.4)
        XCTAssertEqual(control.displayedValue, 0)
        control.moveInteraction(to: 1.4)
        XCTAssertEqual(control.displayedValue, 100)
        control.finishInteraction(at: 1.4)
        XCTAssertEqual(commits, [100])
        control.invalidateInteraction(notify: false)
    }

    func testBoundaryHysteresisRejectsJitter() {
        var feedback = ScrubberBoundaryFeedback()
        XCTAssertEqual(feedback.update(fraction: 0), .start)
        XCTAssertNil(feedback.update(fraction: 0))
        XCTAssertNil(feedback.update(fraction: 0.005))
        XCTAssertNil(feedback.update(fraction: 0))
        XCTAssertNil(feedback.update(fraction: 0.03))
        XCTAssertEqual(feedback.update(fraction: 0), .start)
        XCTAssertEqual(feedback.update(fraction: 1), .end)
        XCTAssertNil(feedback.update(fraction: 0.995))
        XCTAssertNil(feedback.update(fraction: 1))
    }

    func testHapticRateLimitAndInvalidInput() {
        var throttle = HapticThrottle()
        XCTAssertFalse(throttle.allow(at: .nan))
        XCTAssertTrue(throttle.allow(at: 10))
        for time in [10, 10.01, 10.05, 10.1] { XCTAssertFalse(throttle.allow(at: time)) }
        XCTAssertTrue(throttle.allow(at: 10.13))
    }
}
