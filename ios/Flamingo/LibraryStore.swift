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
    static let video = root.appending(path: "Video", directoryHint: .isDirectory)
    static let decoded = root.appending(path: "Decoded", directoryHint: .isDirectory)
    static let database = root.appending(path: "Library.json")
    static func prepare() throws {
        for url in [root, audio, artwork, lyrics, video, decoded] {
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

enum LibraryDestination: Hashable {
    case artist(String)
    case album(String)
}

private actor LibraryDisk {
    func save(_ snapshot: LibrarySnapshot) throws {
        try LibraryPaths.prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: LibraryPaths.database, options: .atomic)
    }
}

actor AudioImporter {
    static let extensions: Set<String> = ["mp3", "m4a", "mp4", "aac", "wav", "wave", "flac", "alac", "aif", "aiff", "caf", "ogg", "oga", "opus", "wma", "ape", "wv", "tta", "tak", "mka", "ac3", "dts", "amr", "mp2", "mpc", "3gp"]
    func files(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
    func importAudio(_ source: URL, systemOnly: Bool) async throws -> Track {
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
            var asset = AVURLAsset(url: destination)
            let playable = (try? await asset.load(.isPlayable)) ?? false
            let systemTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            var decodedName: String?
            var fallbackTags: [String: String] = [:]
            if (!playable || systemTracks.isEmpty) && !systemOnly {
                let name = fingerprint + ".caf"
                fallbackTags = try NativeDecoder.decode(destination, output: LibraryPaths.decoded.appending(path: name))
                decodedName = name
                asset = AVURLAsset(url: LibraryPaths.decoded.appending(path: name))
            }
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard !audioTracks.isEmpty, try await asset.load(.isPlayable) else {
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
            track.originalFilename = source.lastPathComponent
            track.sourceDirectory = source.deletingLastPathComponent().path
            track.modifiedAt = try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            track.decodedFilename = decodedName
            if !fallbackTags.isEmpty {
                track.title = fallbackTags["title"] ?? track.title
                track.artist = fallbackTags["artist"] ?? track.artist
                track.album = fallbackTags["album"] ?? track.album
                track.albumArtist = fallbackTags["album_artist"] ?? ""
                track.embeddedLyrics = fallbackTags["lyrics"] ?? fallbackTags["LYRICS"]
                track.trackNumber = Int((fallbackTags["track"] ?? "0").split(separator: "/").first ?? "0") ?? 0
                track.discNumber = Int((fallbackTags["disc"] ?? "0").split(separator: "/").first ?? "0") ?? 0
                track.codec = fallbackTags["codec"]
                track.sampleRate = fallbackTags["sampleRate"].flatMap(Double.init)
                track.bitsPerSample = fallbackTags["bitsPerSample"].flatMap(Int.init)
                track.bitRate = fallbackTags["bitRate"].flatMap(Int.init)
                track.genre = fallbackTags["genre"]; track.composer = fallbackTags["composer"]
                track.writer = fallbackTags["writer"]; track.author = fallbackTags["author"]; track.year = fallbackTags["date"]
                if let decodedName {
                    let cover = LibraryPaths.decoded.appending(path: decodedName).appendingPathExtension("cover")
                    if FileManager.default.fileExists(atPath: cover.path) {
                        let name = fingerprint + ".cover"
                        let target = LibraryPaths.artwork.appending(path: name)
                        try? FileManager.default.removeItem(at: target)
                        try FileManager.default.moveItem(at: cover, to: target)
                        track.artworkFilename = name
                    }
                }
            } else if let audio = audioTracks.first,
                      let formats = try? await audio.load(.formatDescriptions), let format = formats.first,
                      let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                track.sampleRate = description.mSampleRate
                track.bitsPerSample = Int(description.mBitsPerChannel)
                let code = description.mFormatID
                track.codec = String(bytes: [UInt8((code >> 24) & 255), UInt8((code >> 16) & 255), UInt8((code >> 8) & 255), UInt8(code & 255)], encoding: .ascii)
                track.bitRate = (try? await audio.load(.estimatedDataRate)).map { Int($0) }
            }
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
                let tag = (item.key as? String ?? key).lowercased()
                let common = item.commonKey
                if common == .commonKeyType { track.genre = try? await item.load(.stringValue) }
                if common == .commonKeyAuthor { track.author = try? await item.load(.stringValue) }
                if common == .commonKeyCreator { track.composer = try? await item.load(.stringValue) }
                if common == .commonKeyCreationDate { track.year = try? await item.load(.stringValue) }
                if tag.contains("tpe2") || tag.contains("albumartist") || tag.contains("album_artist") { track.albumArtist = (try? await item.load(.stringValue)) ?? track.albumArtist }
                if tag.contains("tcom") || tag.contains("composer") || tag.contains("©wrt") { track.composer = try? await item.load(.stringValue) }
                if tag.contains("text") || tag.contains("writer") { track.writer = try? await item.load(.stringValue) }
                if tag.contains("author") { track.author = try? await item.load(.stringValue) }
                if tag.contains("tcon") || tag.contains("genre") || tag.contains("©gen") { track.genre = try? await item.load(.stringValue) }
                if tag == "date" || tag.contains("tyer") || tag.contains("tdrc") || tag.contains("tdrl") || tag.contains("©day") { track.year = try? await item.load(.stringValue) }
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
    var playlistAddition: PlaylistAddition?
    var navigationTarget: LibraryDestination?
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
    var tracks: [Track] { snapshot.tracks.filter { !snapshot.hiddenDirectories.contains($0.sourceDirectory ?? "") } }
    var playlists: [Playlist] { snapshot.playlists }
    func artists(for track: Track) -> [String] {
        let separators = AppPreferences.defaults.string(forKey: "artistSeparators") ?? ","
        let values = track.artist.components(separatedBy: CharacterSet(charactersIn: separators))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return values.isEmpty ? [track.artist] : values
    }
    func toggleFollow(_ artist: String) {
        guard ready else { return }
        if snapshot.followedArtists.contains(artist) { snapshot.followedArtists.removeAll { $0 == artist } }
        else { snapshot.followedArtists.append(artist) }
        scheduleSave()
    }
    func track(_ id: UUID) -> Track? { snapshot.tracks.first { $0.id == id } }
    func tracks(for playlist: Playlist) -> [Track] {
        playlist.trackIDs.compactMap(track).filter { !snapshot.hiddenDirectories.contains($0.sourceDirectory ?? "") }
    }
    func setDirectory(_ directory: String, included: Bool) {
        snapshot.hiddenDirectories.removeAll { $0 == directory }
        if !included { snapshot.hiddenDirectories.append(directory) }
        scheduleSave()
    }
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
    func importFiles(_ urls: [URL], folderID: UUID? = nil, quiet: Bool = false) async {
        guard ready, !importing else { return }
        importing = true
        defer { importing = false; importProgress = "" }
        var report = ImportReport()
        let audio = urls.filter { AudioImporter.extensions.contains($0.pathExtension.lowercased()) && $0.deletingLastPathComponent().lastPathComponent != "anim" }
        for (index, url) in audio.enumerated() {
            importProgress = "\(index + 1) / \(audio.count) · \(url.lastPathComponent)"
            do {
                var track = try await importer.importAudio(url, systemOnly: AppPreferences.defaults.bool(forKey: "systemDecoderOnly"))
                track.sourceFolderID = folderID
                if let existing = snapshot.tracks.first(where: { $0.filename == track.filename }) {
                    if existing.sourceFolderID == nil, let folderID, let i = snapshot.tracks.firstIndex(where: { $0.id == existing.id }) {
                        snapshot.tracks[i].sourceFolderID = folderID; snapshot.tracks[i].sourceDirectory = track.sourceDirectory
                    }
                    track = self.track(existing.id) ?? existing; report.duplicates += 1
                } else if AppPreferences.defaults.bool(forKey: "excludeShort"), track.duration < 60 {
                    try? FileManager.default.removeItem(at: LibraryPaths.audio.appending(path: track.filename))
                    if let name = track.decodedFilename { try? FileManager.default.removeItem(at: LibraryPaths.decoded.appending(path: name)) }
                    continue
                } else { snapshot.tracks.append(track); report.imported += 1 }
                let stem = url.deletingPathExtension().lastPathComponent
                let sourceDirectory = url.deletingLastPathComponent().standardizedFileURL
                let candidates = urls.filter {
                    $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(stem) == .orderedSame &&
                    $0.deletingLastPathComponent().standardizedFileURL == sourceDirectory
                }
                for ext in ["ttml", "xml", "lrc"] {
                    if let sidecar = candidates.first(where: { $0.pathExtension.lowercased() == ext }),
                       await attachLyrics(sidecar, for: track.id) { break }
                }
                if let video = urls.first(where: {
                    ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) &&
                    ($0.deletingPathExtension().lastPathComponent == stem && $0 != url && $0.deletingLastPathComponent().standardizedFileURL == sourceDirectory ||
                     $0.deletingLastPathComponent().lastPathComponent == "anim" && $0.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == sourceDirectory && $0.deletingPathExtension().lastPathComponent == Self.safeAlbumName(track.album))
                }) { await importVideo(video, for: track.id) }
            } catch { report.failures.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
        }
        for sidecar in urls where ["ttml", "xml", "lrc"].contains(sidecar.pathExtension.lowercased()) {
            let stem = sidecar.deletingPathExtension().lastPathComponent
            let matches = snapshot.tracks.filter { ($0.originalFilename as NSString?)?.deletingPathExtension == stem }
            let siblings = matches.filter { $0.sourceDirectory == sidecar.deletingLastPathComponent().path }
            let targets = siblings.isEmpty && folderID == nil && matches.count == 1 ? matches : siblings
            for track in targets {
                if sidecar.pathExtension.lowercased() == "lrc", let name = track.lyricsFilename, ["ttml", "xml"].contains((name as NSString).pathExtension) { continue }
                _ = await attachLyrics(sidecar, for: track.id)
            }
        }
        await saveNow()
        if !quiet || !report.failures.isEmpty { importMessage = report.message }
    }
    static func safeAlbumName(_ album: String) -> String {
        album.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func addFolders(_ urls: [URL]) async {
        guard ready else { return }
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                if !snapshot.folders.contains(where: { $0.bookmark == bookmark }) { snapshot.folders.append(MusicFolder(name: url.lastPathComponent, bookmark: bookmark)) }
            } catch { errorMessage = "文件夹授权失败：\(error.localizedDescription)" }
        }
        await saveNow(); await refreshFolders()
    }
    func removeFolder(_ id: UUID) { snapshot.folders.removeAll { $0.id == id }; scheduleSave() }
    func refreshFolders() async {
        guard !importing else { return }
        for folder in snapshot.folders {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: folder.bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if stale, let i = snapshot.folders.firstIndex(where: { $0.id == folder.id }) {
                    snapshot.folders[i].bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                }
                await importFiles(await importer.files(in: url), folderID: folder.id, quiet: true)
            } catch { errorMessage = "无法刷新“\(folder.name)”，请重新授权该文件夹：\(error.localizedDescription)" }
        }
    }
    func importVideo(_ url: URL, for id: UUID) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let asset = AVURLAsset(url: url)
            guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            let name = id.uuidString + "." + url.pathExtension.lowercased()
            let target = LibraryPaths.video.appending(path: name)
            if target != url {
                let staging = LibraryPaths.video.appending(path: UUID().uuidString)
                try FileManager.default.copyItem(at: url, to: staging)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: staging, to: target)
            }
            if let i = snapshot.tracks.firstIndex(where: { $0.id == id }) { snapshot.tracks[i].videoFilename = name; scheduleSave() }
        } catch { errorMessage = "动态封面导入失败：\(error.localizedDescription)" }
    }
    func importLyrics(_ url: URL, for id: UUID) async {
        if !(await attachLyrics(url, for: id, manually: true)) { errorMessage = "未能解析歌词，请选择 UTF-8 或 UTF-16 编码的 LRC / TTML 文件。" }
    }
    @discardableResult private func attachLyrics(_ url: URL, for id: UUID, manually: Bool = false) async -> Bool {
        guard ready, let i = snapshot.tracks.firstIndex(where: { $0.id == id }) else { return false }
        if !manually && snapshot.tracks[i].manualLyrics == true { return false }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16),
                  !LyricsParser.parse(text).isEmpty else {
                return false
            }
            let name = id.uuidString + "." + url.pathExtension.lowercased()
            try data.write(to: LibraryPaths.lyrics.appending(path: name), options: .atomic)
            snapshot.tracks[i].lyricsFilename = name
            snapshot.tracks[i].manualLyrics = manually
            scheduleSave()
            return true
        } catch { return false }
    }
    func lyrics(for track: Track) -> [LyricLine] {
        var sidecar: String?
        if let name = track.lyricsFilename, let data = try? Data(contentsOf: LibraryPaths.lyrics.appending(path: name)),
           let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) { sidecar = text }
        return LyricsParser.preferred(embedded: track.embeddedLyrics, sidecar: sidecar, manual: track.manualLyrics == true)
    }
    func toggleFavorite(_ id: UUID) {
        guard ready, let i = snapshot.tracks.firstIndex(where: { $0.id == id }) else { return }
        snapshot.tracks[i].isFavorite.toggle(); scheduleSave()
    }
    func setFavorite(_ ids: [UUID], value: Bool) {
        guard ready else { return }
        let selected = Set(ids)
        for i in snapshot.tracks.indices where selected.contains(snapshot.tracks[i].id) { snapshot.tracks[i].isFavorite = value }
        scheduleSave()
    }
    func markPlayed(_ id: UUID) {
        guard ready, AppPreferences.defaults.bool(forKey: "listeningHistory"), let i = snapshot.tracks.firstIndex(where: { $0.id == id }) else { return }
        snapshot.tracks[i].lastPlayedAt = Date(); scheduleSave()
        let recent = tracks.filter { $0.lastPlayedAt != nil }.sorted { $0.lastPlayedAt! > $1.lastPlayedAt! }
        let old = Set(recent.dropFirst(50).map(\.id))
        for i in snapshot.tracks.indices where old.contains(snapshot.tracks[i].id) { snapshot.tracks[i].lastPlayedAt = nil }
    }
    func recordListening(_ id: UUID, sessionID: UUID, seconds: Double, qualified: Bool, day: Date) {
        guard ready, AppPreferences.defaults.bool(forKey: "listeningHistory"), seconds > 0, seconds.isFinite, let track = track(id) else { return }
        if let i = snapshot.sessions.firstIndex(where: { $0.id == sessionID }) {
            snapshot.sessions[i].seconds = seconds
            snapshot.sessions[i].countsAsPlay = qualified
        } else {
            var session = ListeningSession(trackID: id, seconds: seconds)
            session.id = sessionID; session.title = track.title; session.artist = track.artist; session.album = track.album
            session.dayStart = day
            session.countsAsPlay = qualified
            snapshot.sessions.append(session)
        }
        scheduleSave()
    }
    func importStatistics(_ url: URL, merge: Bool) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        snapshot.sessions = try ListeningBackup.restore(Data(contentsOf: url), into: snapshot.sessions, tracks: tracks, merge: merge)
        scheduleSave()
    }
    func exportStatistics() throws -> URL {
        let target = LibraryPaths.root.appending(path: "Flamingo-Statistics.json")
        try ListeningBackup.export(snapshot.sessions, tracks: tracks).write(to: target, options: .atomic)
        return target
    }
    func clearStatistics() { snapshot.sessions = []; scheduleSave() }
    func clearHistory() { for i in snapshot.tracks.indices { snapshot.tracks[i].lastPlayedAt = nil }; scheduleSave() }
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
    func restorePlaylist(_ playlist: Playlist) {
        guard ready, !snapshot.playlists.contains(where: { $0.id == playlist.id }) else { return }
        snapshot.playlists.append(playlist); scheduleSave()
    }
    func add(_ trackID: UUID, to playlistID: UUID) {
        add([trackID], to: playlistID)
    }
    func add(_ trackIDs: [UUID], to playlistID: UUID) {
        guard ready, let i = snapshot.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        snapshot.playlists[i].trackIDs.append(contentsOf: trackIDs); scheduleSave()
    }
    func togglePin(_ id: UUID) {
        guard let i = snapshot.playlists.firstIndex(where: { $0.id == id }) else { return }
        let pin = snapshot.playlists[i].isPinned != true
        let next = (snapshot.playlists.compactMap(\.pinOrder).max() ?? -1) + 1
        snapshot.playlists[i].isPinned = pin; snapshot.playlists[i].pinOrder = pin ? next : nil
        scheduleSave()
    }
    func reorderPins(_ ids: [UUID]) {
        for (rank, id) in ids.enumerated() {
            if let i = snapshot.playlists.firstIndex(where: { $0.id == id }), snapshot.playlists[i].isPinned == true { snapshot.playlists[i].pinOrder = rank }
        }
        scheduleSave()
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
        if let name = track.videoFilename { try? FileManager.default.removeItem(at: LibraryPaths.video.appending(path: name)) }
        if let name = track.decodedFilename { try? FileManager.default.removeItem(at: LibraryPaths.decoded.appending(path: name)) }
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
