import XCTest
@testable import Flamingo

@MainActor final class TypographyTests: XCTestCase {
    func testRetiringUnusedFeaturesPreservesPlaybackSettings() {
        let defaults = AppPreferences.defaults
        let keys = ["lyricWeight", "lyricBalance", "animatedCovers", "artworkBlacklist", "artistSeparators", "showVolume", "animatedBackground", "appearance", "playerCorner", "hapticFeedback"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set("ExtraBold", forKey: "lyricWeight")
        defaults.set(true, forKey: "lyricBalance")
        defaults.set(true, forKey: "animatedCovers")
        defaults.set("Album", forKey: "artworkBlacklist")
        defaults.set("/", forKey: "artistSeparators")
        defaults.set(false, forKey: "showVolume")
        defaults.set(false, forKey: "animatedBackground")
        defaults.set("dark", forKey: "appearance")
        defaults.set(50, forKey: "playerCorner")
        defaults.set(false, forKey: "hapticFeedback")
        PlayerPreferences.register()
        XCTAssertNil(defaults.object(forKey: "lyricWeight"))
        XCTAssertNil(defaults.object(forKey: "lyricBalance"))
        XCTAssertNil(defaults.object(forKey: "animatedCovers"))
        XCTAssertNil(defaults.object(forKey: "artworkBlacklist"))
        XCTAssertNil(defaults.object(forKey: "artistSeparators"))
        XCTAssertNil(defaults.object(forKey: "showVolume"))
        XCTAssertNil(defaults.object(forKey: "animatedBackground"))
        XCTAssertNil(defaults.object(forKey: "appearance"))
        XCTAssertNil(defaults.object(forKey: "playerCorner"))
        XCTAssertFalse(defaults.bool(forKey: "hapticFeedback"))
        PlayerPreferences.register()
        XCTAssertNil(defaults.object(forKey: "lyricWeight"))
        XCTAssertNil(defaults.object(forKey: "lyricBalance"))
        XCTAssertNil(defaults.object(forKey: "animatedCovers"))
        XCTAssertNil(defaults.object(forKey: "artworkBlacklist"))
        XCTAssertNil(defaults.object(forKey: "artistSeparators"))
    }
}
