import AVFoundation
import FlamingoCore
import MediaPlayer
import XCTest
@testable import Flamingo

@MainActor final class PlayerTests: XCTestCase {
    private var library: LibraryStore!
    private var player: PlayerStore!
    private var track: Track!
    private var folder: URL!
    private var preferences: [String: Any] = [:]
    private let keys = ["excludeShort", "fadePlayback", "sleepFade", "playbackQueue", "playbackPosition", "lastTrack"]
    override func setUp() async throws {
        let defaults = AppPreferences.defaults
        for key in keys { preferences[key] = defaults.object(forKey: key) }
        defaults.set(false, forKey: "excludeShort"); defaults.set(false, forKey: "fadePlayback")
        defaults.set(0.0, forKey: "sleepFade")
        defaults.removeObject(forKey: "playbackQueue"); defaults.removeObject(forKey: "lastTrack")
        folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: UUID().uuidString + ".wav")
        var data = Data()
        func string(_ text: String) { data.append(Data(text.utf8)) }
        func number<T: FixedWidthInteger>(_ value: T) { var le = value.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
        let count = 44_100
        string("RIFF"); number(UInt32(36 + count * 2)); string("WAVEfmt "); number(UInt32(16))
        number(UInt16(1)); number(UInt16(1)); number(UInt32(22_050)); number(UInt32(44_100)); number(UInt16(2)); number(UInt16(16))
        string("data"); number(UInt32(count * 2))
        for i in 0..<count { number(Int16(sin(Double(i) / 22_050 * 440 * .pi * 2) * 1000)) }
        try data.write(to: url)
        library = LibraryStore(); await library.importFiles([url])
        track = try XCTUnwrap(library.tracks.first { $0.originalFilename == url.lastPathComponent })
        player = PlayerStore(library: library)
    }
    override func tearDown() async throws {
        player?.cancelSleepTimer(); player?.pause(immediate: true)
        if let track { library?.deleteTrack(track.id) }
        await library?.saveNow()
        if let folder { try? FileManager.default.removeItem(at: folder) }
        let defaults = AppPreferences.defaults
        for key in keys { if let value = preferences[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
        player = nil; library = nil; track = nil
    }
    func testSleepAtEndOfTrackKeepsUpcomingEntry() async {
        player.setSleepTimer(mode: .endOfTrack)
        player.play(track, in: [track, track])
        let stopped = await until { self.player.sleepPlan == nil && !self.player.isPlaying }
        XCTAssertTrue(stopped); XCTAssertEqual(player.queue.index, 0); XCTAssertEqual(player.queue.upcoming.count, 1)
    }
    func testSleepAtEndOfQueueReachesLastEntry() async {
        player.setSleepTimer(mode: .endOfQueue)
        player.play(track, in: [track, track])
        let stopped = await until { self.player.sleepPlan == nil && !self.player.isPlaying }
        XCTAssertTrue(stopped); XCTAssertEqual(player.queue.index, 1)
    }
    func testCountdownStopsActualPlaybackAndSupportsExtension() async {
        player.setSleepTimer(mode: .duration, minutes: 30)
        let old = player.sleepDeadline!
        player.extendSleepTimer(minutes: 5)
        XCTAssertEqual(player.sleepDeadline!.timeIntervalSince(old), 300, accuracy: 0.01)
        player.cancelSleepTimer(); XCTAssertNil(player.sleepPlan)
        player.play(track, in: [track])
        player.setSleepTimer(mode: .duration, minutes: 1.0 / 60)
        let stopped = await until { self.player.sleepPlan == nil && !self.player.isPlaying }
        XCTAssertTrue(stopped); XCTAssertLessThan(player.elapsed, 1.9)
    }
    func testQueueAndPositionRestoreWithoutAutoplay() async {
        player.play(track, in: [track, track]); player.pause(immediate: true); player.seek(to: 0.7)
        player.persistQueue()
        let restored = PlayerStore(library: library)
        XCTAssertEqual(restored.queue.entries, player.queue.entries)
        XCTAssertEqual(restored.elapsed, 0.7, accuracy: 0.05)
        XCTAssertFalse(restored.isPlaying)
        restored.pause(immediate: true)
    }
    func testTrackNavigationAndSystemCommandAvailability() {
        player.play(track, in: [track, track, track], startingAt: 1)
        player.pause(immediate: true)
        let commands = MPRemoteCommandCenter.shared()
        XCTAssertTrue(commands.nextTrackCommand.isEnabled)
        XCTAssertTrue(commands.previousTrackCommand.isEnabled)
        XCTAssertTrue(player.next())
        player.pause(immediate: true)
        XCTAssertEqual(player.queue.index, 2)
        XCTAssertFalse(commands.nextTrackCommand.isEnabled)
        player.seek(to: 0.7)
        XCTAssertFalse(player.next())
        XCTAssertEqual(player.elapsed, 0.7, accuracy: 0.01)
        XCTAssertTrue(player.previous())
        player.pause(immediate: true)
        XCTAssertEqual(player.queue.index, 1)
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyPlaybackQueueIndex] as? Int, 1)
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int, 3)
    }
    func testPreviousAfterThreeSecondsSelectsPreviousEntry() async throws {
        // Extend the real WAV fixture to six seconds to exercise the old restart branch.
        var data = try Data(contentsOf: folder.appending(path: track.originalFilename!))
        data.append(Data(repeating: 0, count: 22_050 * 2 * 4))
        func littleEndian(_ value: UInt32) -> Data {
            var value = value.littleEndian
            return withUnsafeBytes(of: &value) { Data($0) }
        }
        data.replaceSubrange(4..<8, with: littleEndian(UInt32(data.count - 8)))
        data.replaceSubrange(40..<44, with: littleEndian(UInt32(data.count - 44)))
        let url = folder.appending(path: UUID().uuidString + ".wav")
        try data.write(to: url)
        await library.importFiles([url])
        let longer = try XCTUnwrap(library.tracks.first { $0.originalFilename == url.lastPathComponent })
        defer { player.pause(immediate: true); _ = library.deleteTrack(longer.id) }
        player.play(longer, in: [track, longer], startingAt: 1)
        player.pause(immediate: true)
        player.seek(to: 4)
        XCTAssertGreaterThan(player.elapsed, 3)
        XCTAssertTrue(player.previous())
        XCTAssertEqual(player.current?.id, track.id)
        XCTAssertEqual(player.queue.index, 0)
    }
    private func until(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<140 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return predicate()
    }

    func testPausedSeekAndSystemMetadataStayConsistent() async {
        player.play(track, in: [track, track])
        player.pause(immediate: true)
        player.seek(to: 0.8)
        XCTAssertEqual(player.elapsed, 0.8, accuracy: 0.01)
        let sought = await until { abs(self.player.lyricPlaybackTime - 0.8) < 0.08 }
        XCTAssertTrue(sought)
        player.synchronizeSystemPlayback()
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPMediaItemPropertyTitle] as? String, track.title)
        XCTAssertEqual((info?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue, 0)
        XCTAssertEqual((info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue ?? -1, 0.8, accuracy: 0.08)
        XCTAssertTrue(MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled)
    }

    func testRapidSeeksKeepLatestAudioAndLyricPosition() async {
        player.play(track, in: [track])
        player.pause(immediate: true)
        let initialRevision = player.seekRevision
        for target in [1.6, 0.2, 1.3, 0.7] { player.seek(to: target) }
        XCTAssertEqual(player.lyricPlaybackTime, 0.7, accuracy: 0.01)
        let settled = await until { self.player.seekRevision > initialRevision + 4 }
        XCTAssertTrue(settled)
        player.synchronizeSystemPlayback()
        XCTAssertEqual(player.elapsed, 0.7, accuracy: 0.08)
        XCTAssertEqual(player.lyricPlaybackTime, player.elapsed, accuracy: 0.02)
        let lyrics = LyricsParser.parse("[00:00.00]First\n[00:00.50]Second\n[00:01.00]Third")
        XCTAssertEqual(LyricsParser.activeIndex(in: lyrics, at: player.lyricPlaybackTime), 1)
        XCTAssertEqual(LyricsParser.activeIndices(in: lyrics, at: player.lyricPlaybackTime), Set([1]))
        // Seek backwards across a line boundary while paused.
        player.seek(to: 0.2)
        let revision = player.seekRevision
        let returned = await until { self.player.seekRevision > revision }
        XCTAssertTrue(returned)
        XCTAssertEqual(player.lyricPlaybackTime, 0.2, accuracy: 0.08)
        XCTAssertEqual(LyricsParser.activeIndex(in: lyrics, at: player.lyricPlaybackTime), 0)
        XCTAssertFalse(player.isPlaying)
    }

    func testMediaServicesResetPreservesPositionWithoutAutoplay() async {
        player.play(track, in: [track, track])
        player.pause(immediate: true)
        player.seek(to: 0.6)
        let before = player.queue.entries
        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: AVAudioSession.sharedInstance())
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(player.queue.entries, before)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.elapsed, 0.6, accuracy: 0.08)
        XCTAssertTrue(MPRemoteCommandCenter.shared().playCommand.isEnabled)
    }
}
