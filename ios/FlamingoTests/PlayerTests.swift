import FlamingoCore
import XCTest
@testable import Flamingo

@MainActor final class PlayerTests: XCTestCase {
    private var library: LibraryStore!
    private var player: PlayerStore!
    private var track: Track!
    private var folder: URL!
    private var preferences: [String: Any] = [:]
    private let keys = ["excludeShort", "fadePlayback", "sleepFade", "listeningHistory", "playbackQueue", "playbackPosition", "lastTrack"]
    override func setUp() async throws {
        let defaults = AppPreferences.defaults
        for key in keys { preferences[key] = defaults.object(forKey: key) }
        defaults.set(false, forKey: "excludeShort"); defaults.set(false, forKey: "fadePlayback")
        defaults.set(0.0, forKey: "sleepFade"); defaults.set(true, forKey: "listeningHistory")
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
        XCTAssertFalse(library.snapshot.sessions.isEmpty)
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
    private func until(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<140 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return predicate()
    }
}
