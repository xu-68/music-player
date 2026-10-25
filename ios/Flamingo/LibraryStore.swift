import AVFoundation
import CryptoKit
import FlamingoCore
import Observation
import UIKit

enum LibraryPaths {
    static let root = URL.documentsDirectory.appending(
        path: ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "FlamingoUITests" : "Flamingo",
        directoryHint: .isDirectory)
    static let audio = root.appending(path: "Audio", directoryHint: .isDirectory)
    static let artwork = root.appending(path: "Artwork", directoryHint: .isDirectory)
    static let lyrics = root.appending(path: "Lyrics", directoryHint: .isDirectory)
    static let database = root.appending(path: "Library.json")
    static func prepare() throws {
        for url in [root, audio, artwork, lyrics] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

struct ImportReport {
    var imported = 0
    var duplicates = 0
    var failures: [String] = []
    var message: String {
        var parts = ["已导入 \(imported) 首歌曲"]
        if duplicates > 0 { parts.append("跳过 \(duplicates) 首重复歌曲") }
        parts += failures
        return parts.joined(separator: "\n")
    }
}

private actor LibraryDisk {
    func save(_ snapshot: LibrarySnapshot) throws {
        try LibraryPaths.prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: LibraryPaths.database, options: .atomic)
    }
}

private actor AudioImporter {
    func importAudio(_ source: URL) async throws -> Track {
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }
        try LibraryPaths.prepare()
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
        let fingerprint = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let filename = fingerprint + "." + source.pathExtension.lowercased()
        let destination = LibraryPaths.audio.appending(path: filename)
        let exists = FileManager.default.fileExists(atPath: destination.path)
        if !exists {
            let staging = LibraryPaths.audio.appending(path: UUID().uuidString + ".importing")
            defer { try? FileManager.default.removeItem(at: staging) }
            try FileManager.default.copyItem(at: source, to: staging)
            try FileManager.default.moveItem(at: staging, to: destination)
        }
        do {
            let asset = AVURLAsset(url: destination)
            let playable = try await asset.load(.isPlayable)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard playable, !audioTracks.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let metadata = try await asset.load(.commonMetadata)
            func string(_ key: AVMetadataKey) async -> String? {
                guard let item = metadata.first(where: { $0.commonKey == key }) else { return nil }
                return try? await item.load(.stringValue)
            }
            let duration = try await asset.load(.duration).seconds
            var track = Track(title: await string(.commonKeyTitle) ?? source.deletingPathExtension().lastPathComponent,
                              artist: await string(.commonKeyArtist) ?? "未知艺人",
                              album: await string(.commonKeyAlbumName) ?? "未知专辑", filename: filename,
                              duration: duration.isFinite ? duration : 0)
            if let item = metadata.first(where: { $0.commonKey == .commonKeyArtwork }),
               let data = try? await item.load(.dataValue), let image = UIImage(data: data) {
                let size = image.size
                let scale = min(1, 1000 / max(size.width, size.height))
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale), format: format)
                    .image { _ in image.draw(in: CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale))) }
                if let jpeg = thumbnail.jpegData(compressionQuality: 0.88) {
                    let name = fingerprint + ".jpg"
                    try jpeg.write(to: LibraryPaths.artwork.appending(path: name), options: .atomic)
                    track.artworkFilename = name
                }
            }
            let allMetadata = try await asset.load(.metadata)
            for item in allMetadata {
                let key = item.identifier?.rawValue ?? String(describing: item.key)
                if key.contains("aART") { track.albumArtist = (try? await item.load(.stringValue)) ?? "" }
                if key.localizedCaseInsensitiveContains("lyrics") || key.contains("©lyr") || key.contains("USLT") {
                    track.embeddedLyrics = try? await item.load(.stringValue)
                }
                if key.contains("trkn"), let data = try? await item.load(.dataValue), data.count >= 4 {
                    track.trackNumber = Int(data[2]) * 256 + Int(data[3])
                }
                if key.contains("disk"), let data = try? await item.load(.dataValue), data.count >= 4 {
                    track.discNumber = Int(data[2]) * 256 + Int(data[3])
                }
            }
            return track
        } catch {
            if !exists { try? FileManager.default.removeItem(at: destination) }
            throw error
        }
    }
}

@MainActor @Observable final class LibraryStore {
    private(set) var snapshot = LibrarySnapshot()
    private(set) var importing = false
    private(set) var importProgress = ""
    var errorMessage: String?
    var importMessage: String?
    @ObservationIgnored private let disk = LibraryDisk()
    @ObservationIgnored private let importer = AudioImporter()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var ready = true

    init() {
        do {
            try LibraryPaths.prepare()
            if FileManager.default.fileExists(atPath: LibraryPaths.database.path) {
                snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: LibraryPaths.database))
                guard snapshot.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            }
        } catch {
            ready = false
            errorMessage = "资料库读取失败，为保护原有数据，已停止写入。请先备份应用 Documents/Flamingo：\(error.localizedDescription)"
        }
    }
    var tracks: [Track] { snapshot.tracks }
    var playlists: [Playlist] { snapshot.playlists }
    func track(_ id: UUID) -> Track? { tracks.first { $0.id == id } }
    func tracks(for playlist: Playlist) -> [Track] { playlist.trackIDs.compactMap(track) }
    var albums: [[Track]] {
        Dictionary(grouping: tracks, by: \.albumKey).values.map { tracks in
            tracks.sorted { ($0.discNumber, $0.trackNumber, $0.title) < ($1.discNumber, $1.trackNumber, $1.title) }
        }.sorted { $0[0].album.localizedStandardCompare($1[0].album) == .orderedAscending }
    }
    func scheduleSave() {
        guard ready else { return }
        saveTask?.cancel()
        saveTask = Task {
            do { try await Task.sleep(for: .milliseconds(400)); await saveNow() }
            catch { return }
        }
    }
    func saveNow() async {
        guard ready else { return }
        do { try await disk.save(snapshot) }
        catch { errorMessage = "保存资料库失败：\(error.localizedDescription)" }
    }
    func importFiles(_ urls: [URL]) async {
        guard ready, !importing else { return }
        importing = true
        defer { importing = false; importProgress = "" }
        var report = ImportReport()
        for (index, url) in urls.enumerated() {
            importProgress = "\(index + 1) / \(urls.count) · \(url.lastPathComponent)"
            do {
                let track = try await importer.importAudio(url)
                if tracks.contains(where: { $0.filename == track.filename }) { report.duplicates += 1 }
                else { snapshot.tracks.append(track); report.imported += 1 }
            } catch { report.failures.append("\(url.lastPathComponent)：无法读取或不支持此音频格式。") }
        }
        await saveNow()
        importMessage = report.message
    }
    func importLyrics(_ url: URL, for id: UUID) async {
        guard ready, let i = snapshot.tracks.firstIndex(where: { $0.id == id }) else { return }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16),
                  !LyricsParser.parse(text).isEmpty else {
                errorMessage = "未能解析歌词，请选择 UTF-8 或 UTF-16 编码的 LRC / TTML 文件。"; return
            }
            let name = id.uuidString + "." + url.pathExtension.lowercased()
            try data.write(to: LibraryPaths.lyrics.appending(path: name), options: .atomic)
            snapshot.tracks[i].lyricsFilename = name
            scheduleSave()
        } catch { errorMessage = "导入歌词失败：\(error.localizedDescription)" }
    }
    func lyrics(for track: Track) -> [LyricLine] {
        if let name = track.lyricsFilename, let data = try? Data(contentsOf: LibraryPaths.lyrics.appending(path: name)),
           let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) { return LyricsParser.parse(text) }
        return track.embeddedLyrics.map(LyricsParser.parse) ?? []
    }
    func toggleFavorite(_ id: UUID) {
        guard ready, let i = snapshot.tracks.firstIndex(where: { $0.id == id }) else { return }
        snapshot.tracks[i].isFavorite.toggle(); scheduleSave()
    }
    func markPlayed(_ id: UUID) {
        guard ready, let i = snapshot.tracks.firstIndex(where: { $0.id == id }) else { return }
        snapshot.tracks[i].lastPlayedAt = Date(); scheduleSave()
    }
    func recordListening(_ id: UUID, seconds: Double) {
        guard ready, seconds > 0, seconds.isFinite else { return }
        let today = Calendar.current.startOfDay(for: Date())
        if let i = snapshot.sessions.firstIndex(where: { $0.trackID == id && Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            snapshot.sessions[i].seconds += seconds
        } else { snapshot.sessions.append(.init(trackID: id, date: today, seconds: seconds)) }
        scheduleSave()
    }
    func createPlaylist(_ name: String, tracks: [UUID] = []) {
        guard ready, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        snapshot.playlists.append(.init(name: name.trimmingCharacters(in: .whitespacesAndNewlines), trackIDs: tracks)); scheduleSave()
    }
    func updatePlaylist(_ playlist: Playlist) {
        guard ready, let i = snapshot.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        snapshot.playlists[i] = playlist; scheduleSave()
    }
    func deletePlaylist(_ id: UUID) {
        guard ready else { return }; snapshot.playlists.removeAll { $0.id == id }; scheduleSave()
    }
    func add(_ trackID: UUID, to playlistID: UUID) {
        guard ready, let i = snapshot.playlists.firstIndex(where: { $0.id == playlistID }),
              !snapshot.playlists[i].trackIDs.contains(trackID) else { return }
        snapshot.playlists[i].trackIDs.append(trackID); scheduleSave()
    }
    func deleteTrack(_ id: UUID) {
        guard ready, let track = track(id) else { return }
        snapshot.tracks.removeAll { $0.id == id }
        for i in snapshot.playlists.indices { snapshot.playlists[i].trackIDs.removeAll { $0 == id } }
        // History is retained so listening totals do not change when files are removed.
        try? FileManager.default.removeItem(at: LibraryPaths.audio.appending(path: track.filename))
        if let name = track.artworkFilename, !snapshot.tracks.contains(where: { $0.artworkFilename == name }) {
            try? FileManager.default.removeItem(at: LibraryPaths.artwork.appending(path: name))
        }
        if let name = track.lyricsFilename { try? FileManager.default.removeItem(at: LibraryPaths.lyrics.appending(path: name)) }
        scheduleSave()
    }
}

@MainActor final class ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() { cache.totalCostLimit = 32 * 1024 * 1024 }
    func image(_ filename: String?) -> UIImage? {
        guard let filename else { return nil }
        if let image = cache.object(forKey: filename as NSString) { return image }
        guard let image = UIImage(contentsOfFile: LibraryPaths.artwork.appending(path: filename).path) else { return nil }
        cache.setObject(image, forKey: filename as NSString, cost: Int(image.size.width * image.size.height * 4))
        return image
    }
}
