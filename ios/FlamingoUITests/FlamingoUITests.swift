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
    func testRedesignedPlayerWhileAudioIsAdvancing() {
        app.buttons["mini-player"].tap()
        waitForExpandedPlayer()
        let toggle = app.buttons["player-play-pause"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "暂停"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 8), .completed)
        let progress = app.descendants(matching: .any)["playback-progress"].firstMatch
        let advancing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let parts = (progress.value as? String ?? "").components(separatedBy: "，")[0].split(separator: ":").compactMap { Double($0) }
            return parts.count == 2 && parts[0] * 60 + parts[1] >= 3
        }, object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [advancing], timeout: 10), .completed)
        capture("14-redesigned-player-playing")
        app.buttons["show-lyrics"].tap()
        XCTAssertTrue(app.buttons["lyric-0"].waitForExistence(timeout: 5))
        capture("15-redesigned-lyrics-playing")
        app.buttons["show-queue"].tap()
        XCTAssertTrue(app.staticTexts["待播清单"].waitForExistence(timeout: 5))
        capture("16-redesigned-queue-playing")
        toggle.tap()
    }
    func testManagedMusicScanAndSourceDeletion() {
        app.buttons["tab-library"].tap()
        app.buttons["library-songs"].tap()
        let song = app.cells.containing(.any, identifier: "song-demo-0.wav").firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 5))
        song.swipeLeft()
        let delete = app.buttons["delete-song"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        let confirm = app.buttons["删除歌曲及音乐文件"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertFalse(app.descendants(matching: .any)["song-demo-0.wav"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["扫描媒体库"].tap()
        XCTAssertTrue(app.alerts["扫描完成"].waitForExistence(timeout: 20))
        app.alerts.buttons["好"].tap()
        app.buttons["library-songs"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["song-demo-0.wav"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["tab-home"].tap()
        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        let automatic = app.switches["auto-scan-music"]
        let scan = app.buttons["scan-music"]
        for _ in 0..<8 where !scan.isHittable { app.swipeUp() }
        XCTAssertTrue(automatic.exists)
        XCTAssertTrue(scan.isHittable)
        XCTAssertFalse(app.buttons["添加音乐文件夹"].exists)
        capture("13-music-settings")
    }
    func testClassicScreensAndPlayer() {
        capture("01-home", verifyingDock: true)
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.navigationBars["资料库"].waitForExistence(timeout: 5))
        capture("02-library", verifyingDock: true)
        app.buttons["mini-player"].tap()
        waitForExpandedPlayer()
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
        XCTAssertFalse(app.buttons["tab-search"].exists)
        app.buttons["library-songs"].tap()
        XCTAssertTrue(app.navigationBars["歌曲"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        XCTAssertTrue(app.buttons["mini-player-next"].isHittable)
        capture("06-songs-search", verifyingDock: true)
    }
    func testPlaybackAndSeekFromLyrics() {
        app.buttons["mini-player"].tap()
        waitForExpandedPlayer()
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
    func testLyricsManualBrowsingAndTypographySettings() {
        app.buttons["mini-player"].tap()
        waitForExpandedPlayer()
        app.buttons["show-lyrics"].tap()
        let lyrics = app.scrollViews["lyrics-scroll"]
        XCTAssertTrue(lyrics.waitForExistence(timeout: 5))
        lyrics.swipeUp()
        let follow = app.buttons["跟随歌词"]
        XCTAssertTrue(follow.waitForExistence(timeout: 5))
        follow.tap()
        XCTAssertTrue(follow.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lyric-0"].isHittable)
        capture("17-system-typography-lyrics")
        app.buttons["close-player"].tap()
        app.buttons["tab-home"].tap()
        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["字体粗细"].exists)
        XCTAssertFalse(app.buttons["ExtraBold"].exists)
        XCTAssertTrue(app.switches["平衡歌词换行"].exists)
        XCTAssertTrue(app.switches["显示音量条"].exists)
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
        waitForExpandedPlayer()
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
        waitForExpandedPlayer()
        app.buttons["show-lyrics"].tap()
        let line = app.buttons["lyric-1"]
        for _ in 0..<4 where !line.isHittable { app.scrollViews["lyrics-scroll"].swipeUp() }
        XCTAssertTrue(line.isHittable); line.tap()
        app.buttons["close-player"].tap()
        XCUIDevice.shared.press(.home)
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 10)); app.buttons["mini-player"].tap()
        waitForExpandedPlayer()
        let progress = app.descendants(matching: .any)["playback-progress"].firstMatch
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (progress.value as? String ?? "").hasPrefix("0:05")
        }, object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
    }
    func testOpenCurrentAlbumFromPlayer() {
        app.buttons["mini-player"].tap()
        waitForExpandedPlayer()
        app.buttons["更多播放选项"].tap()
        XCTAssertTrue(app.buttons["前往专辑"].waitForExistence(timeout: 5))
        app.buttons["前往专辑"].tap()
        XCTAssertTrue(app.navigationBars["沿岸"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mini-player"].exists)
        capture("12-album-detail", verifyingDock: true)
    }
    func testSwipeDismissRestoresHomeAndLibrary() {
        for destination in ["tab-home", "tab-library"] {
            app.buttons[destination].tap()
            let originalFrame = app.buttons["mini-player"].frame
            for _ in 0..<3 {
                app.buttons["mini-player"].tap()
                waitForExpandedPlayer()
                XCTAssertTrue(app.buttons["player-play-pause"].waitForExistence(timeout: 5))
                waitForExpandedPlayer()
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                start.press(forDuration: 0.05, thenDragTo: end)
                let dock = app.buttons["mini-player"]
                let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: dock)
                XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
                XCTAssertEqual(dock.frame.minY, originalFrame.minY, accuracy: 1)
                XCTAssertTrue(app.buttons[destination].isHittable)
            }
            capture("dismiss-\(destination)", verifyingDock: true)
        }
    }
    func testInteractivePlayerCancelAndMiniPlayerButtons() {
        app.buttons["tab-library"].tap()
        app.buttons["library-songs"].tap()
        let miniToggle = app.buttons["mini-player-play-pause"]
        miniToggle.tap()
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "暂停"), object: miniToggle)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 8), .completed)
        XCTAssertFalse(app.buttons["close-player"].isHittable, "The transport button must not expand the player")
        miniToggle.tap()
        app.buttons["mini-player"].tap()
        waitForExpandedPlayer()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        let smallDrag = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.37))
        start.press(forDuration: 0.1, thenDragTo: smallDrag, withVelocity: .slow, thenHoldForDuration: 0.3)
        waitForExpandedPlayer()
        XCTAssertTrue(app.buttons["player-play-pause"].isHittable)
        app.buttons["close-player"].tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["mini-player"])
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        XCTAssertTrue(app.navigationBars["歌曲"].exists)
        capture("18-interactive-player-restored", verifyingDock: true)
    }
    func testAdaptiveScrubberSeeksAndWorksAfterReopening() {
        app.buttons["mini-player"].tap()
        waitForExpandedPlayer()
        let progress = app.descendants(matching: .any)["playback-progress"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        let start = progress.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let end = progress.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.15, thenDragTo: end)
        let sought = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = (progress.value as? String ?? "").components(separatedBy: "，")[0]
            let parts = value.split(separator: ":").compactMap { Double($0) }
            return parts.count == 2 && abs(parts[0] * 60 + parts[1] - 25) <= 1
        }, object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [sought], timeout: 5), .completed)
        app.buttons["close-player"].tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["mini-player"])
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        app.buttons["mini-player"].tap()
        waitForExpandedPlayer()
        progress.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        let soughtAgain = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            // Touch coordinates are rounded to device pixels; a quarter of
            // the track can land just below nine seconds before formatting.
            let value = (progress.value as? String ?? "").components(separatedBy: "，")[0]
            let parts = value.split(separator: ":").compactMap { Double($0) }
            return parts.count == 2 && abs(parts[0] * 60 + parts[1] - 9) <= 1
        }, object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [soughtAgain], timeout: 5), .completed)
        capture("19-adaptive-scrubber-restored")
    }
    private func waitForExpandedPlayer() {
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "expanded"), object: app.buttons["close-player"])
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
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
        let screen = XCUIScreen.main.screenshot()
        if verifyingDock {
            // A hittable accessibility node can remain even when a navigation
            // transition incorrectly paints over the dock. Inspect actual pixels.
            let frame = app.buttons["mini-player"].frame
            let fullImage = screen.image
            // XCTest frames use display points; screenshot UIImage scale may
            // vary, so derive pixel scale from the full-screen app frame.
            let scale = CGFloat(fullImage.cgImage?.width ?? 0) / app.frame.width
            let region = CGRect(x: frame.minX * scale, y: frame.minY * scale,
                                width: frame.width * scale, height: frame.height * scale)
            if let image = fullImage.cgImage?.cropping(to: region) {
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
        let screenshot = XCTAttachment(screenshot: screen)
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
