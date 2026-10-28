import XCTest
@testable import Flamingo

@MainActor final class PlayerMotionTests: XCTestCase {
    func testThirtyPercentDragTracksFingerAndReversalWithoutASecondSpring() {
        let motion = PlayerPresentation()
        motion.settle(expanded: true, reduceMotion: false)
        motion.renderedProgress = 1
        motion.drag(translation: 120, travel: 400)
        XCTAssertEqual(motion.phase, .dragging)
        XCTAssertEqual(motion.progress, 0.7, accuracy: 0.0001)
        motion.drag(translation: 60, travel: 400)
        XCTAssertEqual(motion.progress, 0.85, accuracy: 0.0001)
        motion.drag(translation: .nan, travel: 400)
        XCTAssertEqual(motion.progress, 0.85, accuracy: 0.0001)
        motion.reset()
    }

    func testDragTakesOverRenderedPositionAndCanReverse() {
        let motion = PlayerPresentation()
        motion.settle(expanded: true, reduceMotion: false)
        // Simulate an in-flight render halfway through the opening spring.
        motion.renderedProgress = 0.6
        motion.drag(translation: 20, travel: 400)
        XCTAssertEqual(motion.phase, .dragging)
        XCTAssertEqual(motion.progress, 0.55, accuracy: 0.001)
        motion.drag(translation: -80, travel: 400)
        XCTAssertEqual(motion.progress, 0.8, accuracy: 0.001)
        motion.endDrag(predictedTranslation: -100, travel: 400, reduceMotion: false)
        XCTAssertTrue([.expanding, .expanded].contains(motion.phase))
        XCTAssertEqual(motion.progress, 1)
        motion.reset()
    }

    func testPredictedReleaseChangesOutcomeAtSameFingerPosition() {
        for (prediction, expected) in [(CGFloat(240), PlayerPresentationPhase.collapsing), (-80, .expanding)] {
            let motion = PlayerPresentation()
            motion.settle(expanded: true, reduceMotion: false)
            motion.renderedProgress = 1
            motion.drag(translation: 80, travel: 400)
            XCTAssertEqual(motion.progress, 0.8, accuracy: 0.001)
            motion.endDrag(predictedTranslation: prediction, travel: 400, reduceMotion: false,
                           velocity: prediction > 0 ? 900 : -900)
            XCTAssertEqual(motion.progress, expected == .collapsing ? 0 : 1)
            XCTAssertNotEqual(motion.phase, .dragging)
            motion.reset()
        }
    }

    func testResetRejectsStaleCompletionAndBoundsProgress() async {
        let motion = PlayerPresentation()
        motion.settle(expanded: true, reduceMotion: true)
        motion.renderedProgress = 0.5
        motion.drag(translation: 900, travel: 400)
        XCTAssertEqual(motion.progress, 0)
        motion.drag(translation: -900, travel: 400)
        XCTAssertEqual(motion.progress, 1)
        motion.settle(expanded: false, reduceMotion: true)
        motion.reset()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(motion.phase, .collapsed)
        XCTAssertEqual(motion.progress, 0)
        XCTAssertFalse(motion.isPresented)
    }
}
