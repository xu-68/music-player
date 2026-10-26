import AVFoundation
import XCTest
@testable import Flamingo

final class AudioTests: XCTestCase {
    func testMetadataProbeReadsTagsWithoutCreatingDecodedAudio() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cover = folder.appending(path: "artwork.cover")
        for ext in ["flac", "wma", "ogg", "opus", "wv"] {
            let input = try XCTUnwrap(Bundle(for: AudioTests.self).url(forResource: "tone", withExtension: ext))
            let tags = try NativeDecoder.probe(input, cover: cover)
            XCTAssertEqual(tags["title"], "Decoder fixture", ext)
            XCTAssertEqual(tags["album"], "Decoder Album", ext)
            XCTAssertEqual(tags["composer"], "Test Composer", ext)
            XCTAssertEqual(tags["album_artist"] ?? tags["albumartist"], "Flamingo Ensemble", ext)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        }
        let broken = folder.appending(path: "broken.flac")
        try Data("invalid".utf8).write(to: broken)
        XCTAssertThrowsError(try NativeDecoder.probe(broken, cover: cover))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cover.path))
    }

    func testImporterUsesFFmpegForWMAAndRetainsTags() async throws {
        let input = try XCTUnwrap(Bundle(for: AudioTests.self).url(forResource: "tone", withExtension: "wma"))
        let importer = AudioImporter()
        let track = try await importer.importAudio(input, systemOnly: false)
        XCTAssertEqual(track.title, "Decoder fixture")
        XCTAssertEqual(track.artist, "Flamingo Tests")
        XCTAssertNotNil(track.decodedFilename)
        XCTAssertEqual(track.codec, "wmav2")
        do { _ = try await importer.importAudio(input, systemOnly: true); XCTFail("System-only import should reject WMA on iOS") }
        catch { XCTAssertNotNil(track.decodedFilename) }
    }
    @MainActor func testMusicScanUsesSourceAndPreservesIdentityAndSidecars() async throws {
        let library = LibraryStore()
        let folder = LibraryPaths.audio.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "歌曲 FLAC.flac")
        let fixture = try XCTUnwrap(Bundle(for: AudioTests.self).url(forResource: "tone", withExtension: "flac"))
        try FileManager.default.copyItem(at: fixture, to: source)
        try "<tt><broken>".write(to: folder.appending(path: "歌曲 FLAC.ttml"), atomically: true, encoding: .utf8)
        try "[00:00]本地歌词".write(to: folder.appending(path: "歌曲 FLAC.lrc"), atomically: true, encoding: .utf8)
        await library.scanMusic()
        let track = try XCTUnwrap(library.tracks.first { $0.filename == folder.lastPathComponent + "/歌曲 FLAC.flac" })
        XCTAssertEqual(try LibraryPaths.musicFile(track.filename), source.resolvingSymlinksInPath())
        XCTAssertEqual(track.album, "Decoder Album")
        XCTAssertEqual(library.lyrics(for: track).first?.text, "本地歌词")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 3)
        library.toggleFavorite(track.id)
        library.createPlaylist("扫描回归", tracks: [track.id, track.id])
        let playlist = try XCTUnwrap(library.playlists.last)
        await library.scanMusic()
        XCTAssertTrue(library.track(track.id)?.isFavorite == true)
        XCTAssertEqual(library.tracks.filter { $0.filename == track.filename }.count, 1)
        XCTAssertEqual(library.tracks(for: playlist).count, 2)
        XCTAssertTrue(library.deleteTrack(track.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertNil(library.track(track.id))
        XCTAssertTrue(library.playlists.first { $0.id == playlist.id }?.trackIDs.isEmpty == true)
        await library.scanMusic()
        XCTAssertNil(library.track(track.id), "Deleted source must not reappear on scan")
        library.deletePlaylist(playlist.id); await library.saveNow()
    }
    @MainActor func testMusicScanReconcilesFilesDeletionAndReportsCorruptAudio() async throws {
        let library = LibraryStore()
        let folder = LibraryPaths.audio.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "external.flac")
        let fixture = try XCTUnwrap(Bundle(for: AudioTests.self).url(forResource: "tone", withExtension: "flac"))
        try FileManager.default.copyItem(at: fixture, to: source)
        let broken = folder.appending(path: "broken.mp3")
        try Data("invalid audio".utf8).write(to: broken)
        await library.scanMusic()
        let track = try XCTUnwrap(library.tracks.first { $0.filename == folder.lastPathComponent + "/external.flac" })
        XCTAssertTrue(library.importMessage?.contains("broken.mp3") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path), "Failed scans must retain source files")
        try FileManager.default.removeItem(at: source)
        await library.scanMusic()
        XCTAssertNil(library.track(track.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path))
        await library.saveNow()
    }
    @MainActor func testMusicMigrationPreservesTrackAndPlaylist() async throws {
        let library = LibraryStore()
        let fixture = try XCTUnwrap(Bundle(for: AudioTests.self).url(forResource: "tone", withExtension: "flac"))
        let name = UUID().uuidString + ".flac"
        let source = LibraryPaths.audio.appending(path: name)
        try FileManager.default.copyItem(at: fixture, to: source)
        await library.scanMusic()
        let track = try XCTUnwrap(library.tracks.first { $0.filename == name })
        library.toggleFavorite(track.id)
        library.createPlaylist("迁移回归", tracks: [track.id])
        let playlist = try XCTUnwrap(library.playlists.last)
        await library.saveNow()
        let legacy = LibraryPaths.root.appending(path: "Audio", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: legacy.appending(path: name))
        let upgraded = LibraryStore()
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(upgraded.track(track.id)?.isFavorite == true)
        XCTAssertEqual(upgraded.playlists.first { $0.id == playlist.id }?.trackIDs, [track.id])
        upgraded.deleteTrack(track.id); upgraded.deletePlaylist(playlist.id); await upgraded.saveNow()
    }
    func testMusicPathsRejectTraversalAndSymlinkEscape() throws {
        try LibraryPaths.prepare()
        XCTAssertThrowsError(try LibraryPaths.musicFile("../Library.json"))
        let link = LibraryPaths.audio.appending(path: UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL.temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: link) }
        XCTAssertThrowsError(try LibraryPaths.musicFile(link.lastPathComponent + "/external.mp3"))
    }
    func testExtendedAudioFormatsDecodeToPlayablePCM() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // Repeated calls also cover native channel-layout allocation/cleanup.
        for ext in ["wma", "ogg", "opus", "flac", "wv", "wma", "opus", "flac"] {
            let input = try XCTUnwrap(Bundle(for: AudioTests.self).url(forResource: "tone", withExtension: ext), "Generate synthetic fixtures before testing")
            let output = folder.appending(path: UUID().uuidString + ".caf")
            let tags = try NativeDecoder.decode(input, output: output)
            XCTAssertEqual(tags["title"], "Decoder fixture", ext)
            let asset = AVURLAsset(url: output)
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration).seconds
            XCTAssertTrue(playable, ext)
            XCTAssertEqual(duration, 0.2, accuracy: 0.08, ext)
            let pcm = try AVAudioFile(forReading: output)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: pcm.processingFormat, frameCapacity: AVAudioFrameCount(pcm.length)))
            try pcm.read(into: buffer)
            let samples = try XCTUnwrap(buffer.floatChannelData).pointee
            let count = Int(buffer.frameLength)
            XCTAssertGreaterThan(count, 0, ext)
            let energy = UnsafeBufferPointer(start: samples, count: count).reduce(0.0) { $0 + Double($1) * Double($1) }
            let rms = sqrt(energy / Double(max(1, count)))
            XCTAssertTrue(rms.isFinite, ext); XCTAssertGreaterThan(rms, 0.01, ext)
        }
    }
    func testNativeFFmpegDecodeAndMetadata() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "tone.wav")
        let output = folder.appending(path: "tone.caf")
        let rate: UInt32 = 44_100, frames: UInt32 = 4_410, size = frames * 2
        var wav = Data()
        func text(_ value: String) { wav.append(Data(value.utf8)) }
        func u32(_ value: UInt32) { var little = value.littleEndian; withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var little = value.littleEndian; withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) } }
        text("RIFF"); u32(size + 36); text("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(rate); u32(rate * 2); u16(2); u16(16); text("data"); u32(size)
        for sample in 0..<frames { u16(UInt16(bitPattern: Int16(sin(Double(sample) / Double(rate) * 440 * .pi * 2) * 10_000))) }
        try wav.write(to: input)
        let tags = try NativeDecoder.decode(input, output: output)
        XCTAssertEqual(tags["codec"], "pcm_s16le")
        XCTAssertEqual(tags["sampleRate"], "44100")
        let asset = AVURLAsset(url: output)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration).seconds
        XCTAssertTrue(playable)
        XCTAssertEqual(duration, 0.1, accuracy: 0.005)
        XCTAssertGreaterThan(try Data(contentsOf: output).count, Int(size))
    }
    func testBrokenFileFailsWithoutLeavingOutput() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "broken.ape"), output = folder.appending(path: "broken.caf")
        try Data("invalid audio".utf8).write(to: input)
        XCTAssertThrowsError(try NativeDecoder.decode(input, output: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
}
