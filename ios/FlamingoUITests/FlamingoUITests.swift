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
    func testCreatePlaylistWithDuplicateSongsAndRestoreAfterRelaunch() {
        app.buttons["tab-library"].tap()
        app.buttons["library-playlists"].tap()
        app.buttons["新建歌单"].tap()
        let name = app.textFields["playlist-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Test playlist")
        app.buttons["playlist-add-songs"].tap()
        let song = app.buttons["picker-song-海风经过"]
        XCTAssertTrue(song.waitForExistence(timeout: 5)); song.tap(); song.tap()
        app.navigationBars["添加歌曲"].buttons["完成"].tap()
        app.navigationBars["新建歌单"].buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["Test playlist"].waitForExistence(timeout: 5))
        capture("08-playlists")
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["tab-library"].tap(); app.buttons["library-playlists"].tap()
        XCTAssertTrue(app.staticTexts["Test playlist"].waitForExistence(timeout: 5))
        app.staticTexts["Test playlist"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "海风经过，Flamingo Studio")).count, 2)
        capture("09-playlist-detail")
    }
    func testSleepTimerModesAndSettings() {
        app.buttons["mini-player"].tap()
        app.buttons["更多播放选项"].tap()
        app.buttons["睡眠定时"].tap()
        let start = app.buttons["start-sleep-timer"]
        XCTAssertTrue(start.waitForExistence(timeout: 5)); start.tap()
        XCTAssertTrue(app.buttons["取消定时"].waitForExistence(timeout: 5))
        app.buttons["延长 5 分钟"].tap()
        capture("10-sleep-timer")
        app.buttons["取消定时"].tap()
        XCTAssertFalse(app.buttons["取消定时"].exists)
        app.navigationBars["睡眠定时"].buttons["完成"].tap()
        app.buttons["close-player"].tap()
        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        capture("11-settings")
    }
    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
