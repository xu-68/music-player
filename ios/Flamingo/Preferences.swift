import Foundation

enum PlayerPreferences {
    static func register() {
        // Retire removed feature preferences; preserve playback and library settings.
        for key in ["lyricWeight", "listeningHistory", "statsPeriod"] {
            AppPreferences.defaults.removeObject(forKey: key)
        }
        AppPreferences.defaults.register(defaults: [
            "appearance": "system", "animatedBackground": true, "lyricBlur": false,
            "showVolume": true, "showTranslation": true,
            "lyricBalance": false, "playerCorner": 30.0,
            "animatedCovers": false, "artworkBlacklist": "",
            "artistSeparators": ",", "autoScanMusic": true, "excludeShort": false,
            "fadePlayback": true, "hapticFeedback": true, "systemDecoderOnly": false,
            "sleepFade": 5.0, "songSort": "标题", "sortDescending": false
        ])
    }
}
