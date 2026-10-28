import FlamingoCore
import UIKit

#if DEBUG
// Explicit UI-testing mode only. Normal launches always use the user's library.
// Audio and artwork are generated locally and contain no commercial music or covers.
@MainActor enum DemoLibrary {
    static func prepare() {
        if ProcessInfo.processInfo.arguments.contains("--reset-ui-testing"),
           LibraryPaths.root.lastPathComponent == "FlamingoUITests" {
            try? FileManager.default.removeItem(at: LibraryPaths.root)
            AppPreferences.defaults.removePersistentDomain(forName: "org.flamingo.local.uitests")
        }
        guard !FileManager.default.fileExists(atPath: LibraryPaths.database.path) else { return }
        do {
            try LibraryPaths.prepare()
            var snapshot = LibrarySnapshot()
            let records: [(String, String, String, UIColor, UIColor)] = [
                ("海风经过", "Flamingo Studio", "沿岸", UIColor(red: 0.08, green: 0.3, blue: 0.39, alpha: 1), UIColor(red: 0.84, green: 0.7, blue: 0.49, alpha: 1)),
                ("暮色慢行", "Flamingo Studio", "日落以后", UIColor(red: 0.48, green: 0.12, blue: 0.24, alpha: 1), UIColor(red: 0.95, green: 0.53, blue: 0.27, alpha: 1)),
                ("凌晨四点", "Flamingo Studio", "微光", UIColor(red: 0.12, green: 0.17, blue: 0.28, alpha: 1), UIColor(red: 0.5, green: 0.61, blue: 0.69, alpha: 1)),
                ("在路上", "Flamingo Studio", "山间来信", UIColor(red: 0.15, green: 0.27, blue: 0.19, alpha: 1), UIColor(red: 0.66, green: 0.68, blue: 0.46, alpha: 1))
            ]
            for (index, record) in records.enumerated() {
                let filename = "demo-\(index).wav"
                try makeAudio(frequency: 130.81 * pow(1.12246, Double(index)), duration: 36).write(to: LibraryPaths.audio.appending(path: filename))
                let artwork = "demo-\(index).jpg"
                let image = makeArtwork(title: record.2, index: index, first: record.3, second: record.4)
                try image.jpegData(compressionQuality: 0.9)?.write(to: LibraryPaths.artwork.appending(path: artwork))
                let lyrics = "[00:00.00]这是用于界面验证的原创测试音频\n[00:05.00]海风轻轻经过\n[00:10.00]让时间慢下来\n[00:15.00]沿着光的方向\n[00:20.00]听见此刻\n[00:28.00]音乐留在这里"
                var track = Track(title: record.0, artist: record.1, album: record.2, filename: filename,
                                  artworkFilename: artwork, embeddedLyrics: lyrics, duration: 36, trackNumber: 1, isFavorite: index == 0)
                snapshot.tracks.append(track)
            }
            snapshot.playlists = [.init(name: "慢慢听", trackIDs: snapshot.tracks.map(\.id))]
            try JSONEncoder().encode(snapshot).write(to: LibraryPaths.database, options: .atomic)
            AppPreferences.defaults.set(snapshot.tracks.first?.id.uuidString, forKey: "lastTrack")
            AppPreferences.defaults.set("dark", forKey: "appearance")
            AppPreferences.defaults.set(false, forKey: "animatedBackground")
            AppPreferences.defaults.set(false, forKey: "autoScanMusic")
        } catch { assertionFailure("UI fixture creation failed: \(error)") }
    }
    private static func makeArtwork(title: String, index: Int, first: UIColor, second: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 700, height: 700), format: format).image { renderer in
            let context = renderer.cgContext
            let colors = [first.cgColor, second.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 560, y: 700), options: [])
            context.setFillColor(UIColor.white.withAlphaComponent(0.17).cgColor)
            for i in 0..<7 {
                let y = 200 + CGFloat(i) * 65
                let path = UIBezierPath(); path.move(to: CGPoint(x: -50, y: y))
                path.addCurve(to: CGPoint(x: 750, y: y + 100), controlPoint1: CGPoint(x: 210, y: y - 180), controlPoint2: CGPoint(x: 470, y: y + 170))
                path.addLine(to: CGPoint(x: 750, y: 750)); path.addLine(to: CGPoint(x: -50, y: 750)); path.close(); path.fill()
            }
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .left
            (title as NSString).draw(at: CGPoint(x: 42, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 62, weight: .light), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
            ("FLAMINGO STUDIO / 0\(index + 1)" as NSString).draw(at: CGPoint(x: 44, y: 635), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 16, weight: .medium), .foregroundColor: UIColor.white.withAlphaComponent(0.7)])
        }
    }
    private static func makeAudio(frequency: Double, duration: Double) -> Data {
        let sampleRate: UInt32 = 22050
        let count = Int(Double(sampleRate) * duration)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        data.append(contentsOf: "RIFF".utf8); append(UInt32(36 + count * 2)); data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(sampleRate); append(sampleRate * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: "data".utf8); append(UInt32(count * 2))
        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let fade = min(1, min(t / 2, (duration - t) / 2))
            let wave = sin(t * frequency * .pi * 2) + 0.35 * sin(t * frequency * 1.5 * .pi * 2)
            append(Int16(wave * fade * 1900))
        }
        return data
    }
}
#endif
