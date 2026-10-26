import XCTest
import UIKit

final class FlamingoUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing"]
        if app.state != .notRunning { app.terminate(); XCTAssertTrue(app.wait(for: .notRunning, timeout: 10)) }
        app.launch()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 20))
    }
    func testClassicScreensAndPlayer() {
        capture("01-home", verifyingDock: true)
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.navigationBars["资料库"].waitForExistence(timeout: 5))
        capture("02-library", verifyingDock: true)
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
        capture("06-stats", verifyingDock: true)
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
        capture("08-playlists", verifyingDock: true)
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["tab-library"].tap(); app.buttons["library-playlists"].tap()
        XCTAssertTrue(app.staticTexts["Test playlist"].waitForExistence(timeout: 5))
        app.staticTexts["Test playlist"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "海风经过，Flamingo Studio")).count, 2)
        capture("09-playlist-detail", verifyingDock: true)
    }
    func testSleepTimerModesAndSettings() {
        app.buttons["mini-player"].tap()
        app.buttons["更多播放选项"].tap()
        app.buttons["睡眠定时"].tap()
        let start = app.buttons["start-sleep-timer"]
        XCTAssertTrue(start.waitForExistence(timeout: 5)); start.tap()
        XCTAssertTrue(app.buttons["取消定时"].waitForExistence(timeout: 5))
        app.buttons["延长 5 分钟"].tap()
        let remaining = app.staticTexts["sleep-remaining"]
        let extended = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let text = remaining.label
            let minutes = text.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
            return minutes == 34 || minutes == 35
        }, object: remaining)
        XCTAssertEqual(XCTWaiter.wait(for: [extended], timeout: 5), .completed)
        capture("10-sleep-timer")
        app.buttons["取消定时"].tap()
        XCTAssertFalse(app.buttons["取消定时"].exists)
        app.navigationBars["睡眠定时"].buttons["完成"].tap()
        app.buttons["close-player"].tap()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["mini-player"])
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        capture("11-settings")
    }
    func testPlaybackPositionSurvivesAppRestart() {
        app.buttons["mini-player"].tap()
        app.buttons["show-lyrics"].tap()
        let line = app.buttons["lyric-1"]
        for _ in 0..<4 where !line.isHittable { app.scrollViews["lyrics-scroll"].swipeUp() }
        XCTAssertTrue(line.isHittable); line.tap()
        app.buttons["close-player"].tap()
        XCUIDevice.shared.press(.home)
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 10)); app.buttons["mini-player"].tap()
        let progress = app.descendants(matching: .any)["playback-progress"].firstMatch
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (progress.value as? String ?? "").hasPrefix("0:05")
        }, object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
    }
    func testOpenCurrentAlbumFromPlayer() {
        app.buttons["mini-player"].tap(); app.buttons["更多播放选项"].tap()
        app.buttons["前往专辑"].tap()
        XCTAssertTrue(app.navigationBars["沿岸"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mini-player"].exists)
        capture("12-album-detail", verifyingDock: true)
    }
    private func capture(_ name: String, verifyingDock: Bool = false) {
        // Existence checks can pass during the native navigation push. Capture
        // after its transition settles. Only root/navigation pages expose the dock;
        // player overlays and presented sheets intentionally cover it.
        if verifyingDock {
            let usable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["mini-player"])
            XCTAssertEqual(XCTWaiter.wait(for: [usable], timeout: 5), .completed)
        }
        Thread.sleep(forTimeInterval: 0.7)
        if verifyingDock {
            // A hittable accessibility node can remain even when a navigation
            // transition incorrectly paints over the dock. Inspect actual pixels.
            let dockImage = app.buttons["mini-player"].screenshot().image
            if let image = dockImage.cgImage {
                var pixels = [UInt8](repeating: 0, count: 32 * 16 * 4)
                let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
                    guard let context = CGContext(data: bytes.baseAddress, width: 32, height: 16,
                        bitsPerComponent: 8, bytesPerRow: 32 * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                    context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 16))
                    return true
                }
                XCTAssertTrue(rendered)
                let visible = stride(from: 0, to: pixels.count, by: 4).filter {
                    max(pixels[$0], max(pixels[$0 + 1], pixels[$0 + 2])) > 12
                }.count
                XCTAssertGreaterThan(visible, 32 * 16 / 10, "Mini player must render visibly on \(name)")
            } else { XCTFail("Could not inspect the mini-player screenshot") }
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
