import Foundation
import SwiftUI

enum PlayerPreferences {
    static func register() {
        AppPreferences.defaults.register(defaults: [
            "appearance": "system", "animatedBackground": true, "lyricBlur": false,
            "showVolume": true, "showTranslation": true, "lyricWeight": "ExtraBold",
            "lyricBalance": false, "barBlur": false, "playerCorner": 30.0,
            "animatedCovers": false, "artworkBlacklist": "",
            "artistSeparators": ",", "autoScanMusic": true, "excludeShort": false,
            "fadePlayback": true, "listeningHistory": true, "systemDecoderOnly": false,
            "sleepFade": 5.0, "songSort": "标题", "sortDescending": false
        ])
    }
    static var lyricWeight: Font.Weight {
        switch AppPreferences.defaults.string(forKey: "lyricWeight") {
        case "Thin": return .thin
        case "ExtraLight": return .ultraLight
        case "Light": return .light
        case "Regular": return .regular
        case "Medium": return .medium
        case "SemiBold": return .semibold
        case "Bold": return .bold
        case "Black": return .black
        default: return .heavy
        }
    }
}
