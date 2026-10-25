import XCTest

final class FlamingoUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 20))
    }
    func testClassicScreensAndPlayer() {
        capture("01-home")
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.navigationBars["资料库"].waitForExistence(timeout: 5))
        capture("02-library")
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["player-play-pause"].waitForExistence(timeout: 5))
        capture("03-now-playing")
        app.buttons["show-lyrics"].tap()
        XCTAssertTrue(app.buttons["lyric-0"].waitForExistence(timeout: 5))
        capture("04-lyrics")
        app.buttons["show-queue"].tap()
        XCTAssertTrue(app.staticTexts["待播清单"].waitForExistence(timeout: 5))
        capture("05-queue")
        app.buttons["close-player"].tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 5))
        app.buttons["tab-stats"].tap()
        XCTAssertTrue(app.navigationBars["统计"].waitForExistence(timeout: 5))
        capture("06-stats")
    }
    func testPlaybackAndSeekFromLyrics() {
        app.buttons["mini-player"].tap()
        let toggle = app.buttons["player-play-pause"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "暂停"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 8), .completed)
        toggle.tap()
        let pausedBeforeSeek = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "播放"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [pausedBeforeSeek], timeout: 5), .completed)
        app.buttons["show-lyrics"].tap()
        let lyric = app.buttons["lyric-1"]
        let lyricsScroll = app.scrollViews["lyrics-scroll"]
        for _ in 0..<4 where !lyric.isHittable { lyricsScroll.swipeUp() }
        XCTAssertTrue(lyric.waitForExistence(timeout: 5))
        XCTAssertTrue(lyric.isHittable)
        lyric.tap()
        let progress = app.descendants(matching: .any)["playback-progress"].firstMatch
        XCTAssertTrue(progress.exists)
        let sought = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = (progress.value as? String ?? "").components(separatedBy: "，")[0]
            let parts = value.split(separator: ":").compactMap { Double($0) }
            guard parts.count == 2 else { return false }
            let seconds = parts[0] * 60 + parts[1]
            return seconds >= 5 && seconds < 10
        }, object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [sought], timeout: 5), .completed)
        capture("07-playing-lyrics")
        toggle.tap()
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "暂停"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 5), .completed)
        toggle.tap()
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "播放"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 5), .completed)
    }
    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
