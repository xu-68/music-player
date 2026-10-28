import XCTest
@testable import Flamingo

@MainActor final class TypographyTests: XCTestCase {
    func testRetiringLyricWeightPreservesOtherUserSettings() {
        let defaults = AppPreferences.defaults
        let keys = ["lyricWeight", "lyricBalance", "showVolume", "animatedBackground"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set("ExtraBold", forKey: "lyricWeight")
        defaults.set(true, forKey: "lyricBalance")
        defaults.set(false, forKey: "showVolume")
        defaults.set(false, forKey: "animatedBackground")
        PlayerPreferences.register()
        XCTAssertNil(defaults.object(forKey: "lyricWeight"))
        XCTAssertTrue(defaults.bool(forKey: "lyricBalance"))
        XCTAssertFalse(defaults.bool(forKey: "showVolume"))
        XCTAssertFalse(defaults.bool(forKey: "animatedBackground"))
        PlayerPreferences.register()
        XCTAssertNil(defaults.object(forKey: "lyricWeight"))
        XCTAssertTrue(defaults.bool(forKey: "lyricBalance"))
    }
}
