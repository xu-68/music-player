import Foundation

enum PlayerPreferences {
    static func register() {
        // Retire removed feature preferences; preserve playback and library settings.
        for key in ["lyricWeight", "listeningHistory", "statsPeriod",
                    "lyricBalance", "animatedCovers", "artworkBlacklist", "artistSeparators",
                    "appearance", "animatedBackground", "showVolume", "playerCorner", "lyricBlur"] {
            AppPreferences.defaults.removeObject(forKey: key)
        }
        AppPreferences.defaults.register(defaults: [
            "showTranslation": true,
            "autoScanMusic": true, "excludeShort": false,
            "fadePlayback": true, "hapticFeedback": true, "systemDecoderOnly": false,
            "sleepFade": 5.0, "songSort": "标题", "sortDescending": false
        ])
    }
}
