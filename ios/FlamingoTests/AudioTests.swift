import AVFoundation
import XCTest
@testable import Flamingo

final class AudioTests: XCTestCase {
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
    @MainActor func testFolderRefreshDeduplicatesAndFallsBackToLRC() async throws {
        let defaults = AppPreferences.defaults
        let old = defaults.object(forKey: "excludeShort")
        defaults.set(false, forKey: "excludeShort")
        defer { if let old { defaults.set(old, forKey: "excludeShort") } else { defaults.removeObject(forKey: "excludeShort") } }
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = try XCTUnwrap(Bundle(for: AudioTests.self).url(forResource: "tone", withExtension: "flac"))
        let filename = UUID().uuidString
        try FileManager.default.copyItem(at: input, to: folder.appending(path: filename + ".flac"))
        try "<tt><broken>".write(to: folder.appending(path: filename + ".ttml"), atomically: true, encoding: .utf8)
        try "[00:00.00]Fallback lyric".write(to: folder.appending(path: filename + ".lrc"), atomically: true, encoding: .utf8)
        let library = LibraryStore()
        await library.addFolders([folder])
        let track = try XCTUnwrap(library.tracks.first { $0.originalFilename == filename + ".flac" })
        XCTAssertEqual(library.lyrics(for: track).first?.text, "Fallback lyric")
        let count = library.tracks.count
        await library.refreshFolders()
        XCTAssertEqual(library.tracks.count, count)
        let sourceDirectory = try XCTUnwrap(track.sourceDirectory)
        library.setDirectory(sourceDirectory, included: false)
        XCTAssertFalse(library.tracks.contains { $0.id == track.id })
        XCTAssertNotNil(library.track(track.id), "Hiding a folder must preserve queue metadata")
        await library.refreshFolders()
        XCTAssertEqual(library.snapshot.tracks.filter { $0.filename == track.filename }.count, 1)
        library.setDirectory(sourceDirectory, included: true)
        XCTAssertEqual(library.tracks.count, count)
        let video = try XCTUnwrap(Bundle(for: AudioTests.self).url(forResource: "cover", withExtension: "mp4"))
        await library.importVideo(video, for: track.id)
        let updated = try XCTUnwrap(library.track(track.id))
        let videoName = try XCTUnwrap(updated.videoFilename)
        let asset = AVURLAsset(url: LibraryPaths.video.appending(path: videoName))
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertFalse(videoTracks.isEmpty)
        for entry in library.snapshot.folders where entry.name == folder.lastPathComponent { library.removeFolder(entry.id) }
        library.deleteTrack(track.id); await library.saveNow()
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
