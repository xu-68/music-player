import XCTest
@testable import FlamingoCore

final class CoreTests: XCTestCase {
    func testLRCFractionsTranslationsAndOffset() {
        let lines = LyricsParser.parse("[offset:-200]\n[00:01.250]Hello\n[00:01.250]你好\n[00:05]World\n[00:09.500]")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].start, 1.05, accuracy: 0.0001)
        XCTAssertEqual(lines[0].translation, "你好")
        XCTAssertEqual(lines[0].end, 4.8)
        XCTAssertNil(LyricsParser.activeIndex(in: lines, at: 0))
        XCTAssertEqual(LyricsParser.activeIndex(in: lines, at: 4.8), 1)
        XCTAssertNil(LyricsParser.activeIndex(in: lines, at: .nan))
    }
    func testRepeatedTimestampsAndWordTiming() {
        let repeated = LyricsParser.parse("[00:01][00:03]Chorus")
        XCTAssertEqual(repeated.map(\.start), [1, 3])
        let enhanced = LyricsParser.parse("[00:01.00]Hello <00:01.50>world<00:02.00>\n[00:04]Next")
        XCTAssertEqual(enhanced[0].text, "Hello world")
        XCTAssertEqual(enhanced[0].words.map(\.start), [1, 1.5])
        XCTAssertEqual(enhanced[0].words[1].end, 2)
        let square = LyricsParser.parse("[00:01]你[00:02]好[00:03]")
        XCTAssertEqual(square[0].words.map(\.text), ["你", "好"])
    }
    func testTTMLWordsEntitiesAndTranslation() {
        let xml = #"<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body><div><p begin="00:01.000" end="00:05.000"><span begin="00:01.000" end="00:02.000">Hello </span><span begin="00:02.000" end="00:04.000">&amp; world</span><span ttm:role="x-translation">你好，世界</span></p><p begin="00:05.000" dur="2s">Next</p></div></body></tt>"#
        let lines = LyricsParser.parse(xml)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, "Hello & world")
        XCTAssertEqual(lines[0].translation, "你好，世界")
        XCTAssertEqual(lines[0].words.count, 2)
        XCTAssertEqual(lines[0].words.last?.start, 2)
        XCTAssertEqual(lines[1].end, 7)
    }
    func testTTMLOffsetDurationsAndMalformedInput() {
        let xml = #"<tt xmlns="http://www.w3.org/ns/ttml"><body begin="2s"><div><p begin="1s" dur="3s"><span begin="0s" dur="1s">First</span><br/>line</p></div></body></tt>"#
        let lines = LyricsParser.parse(xml)
        XCTAssertEqual(lines.first?.start, 1)
        XCTAssertEqual(lines.first?.end, 4)
        XCTAssertEqual(lines.first?.text, "First\nline")
        XCTAssertTrue(LyricsParser.parse("<tt><broken>").isEmpty)
        XCTAssertTrue(LyricsParser.parse("No timestamps").isEmpty)
    }
    func testQueueEndRepeatAndManualNext() {
        let ids = [UUID(), UUID(), UUID()]
        var queue = PlaybackQueue()
        queue.replace(with: ids)
        XCTAssertEqual(queue.current?.trackID, ids[0])
        queue.repeatMode = .one
        XCTAssertTrue(queue.advance(automatic: true))
        XCTAssertEqual(queue.current?.trackID, ids[0])
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.current?.trackID, ids[1])
        XCTAssertTrue(queue.advance())
        XCTAssertFalse(queue.advance())
        queue.repeatMode = .all
        XCTAssertTrue(queue.advance(automatic: true))
        XCTAssertEqual(queue.current?.trackID, ids[0])
        XCTAssertTrue(queue.previous())
        XCTAssertEqual(queue.current?.trackID, ids[2])
    }
    func testFuzzySearchMetadataRanking() {
        var exact = Track(title: "Hello", artist: "A", album: "One", filename: "a.mp3")
        exact.composer = "Example Composer"
        let prefix = Track(title: "Hello world", filename: "b.mp3")
        let artist = Track(title: "Different", artist: "Hello", filename: "c.mp3")
        XCTAssertEqual(MusicSearch.ranked([artist, prefix, exact], query: "hello").map(\.id), [exact.id, prefix.id, artist.id])
        XCTAssertEqual(MusicSearch.ranked([exact], query: "helo").first?.id, exact.id)
        XCTAssertEqual(MusicSearch.ranked([exact], query: "Composer").first?.id, exact.id)
        XCTAssertTrue(MusicSearch.ranked([exact], query: "no match anywhere").isEmpty)
    }
    func testSleepModes() throws {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(SleepPlan(mode: .duration, minutes: 1, now: now).deadline, now.addingTimeInterval(60))
        XCTAssertNil(SleepPlan(mode: .endOfTrack).deadline)
        XCTAssertNil(SleepPlan(mode: .endOfQueue).deadline)
    }
    func testArtistReleasesClassifyPrimaryAndFeatured() {
        var album = (0..<7).map { Track(title: "Album song \($0)", artist: "Singer", album: "Album", albumArtist: "Singer", filename: "\($0).wav", duration: 300) }
        for i in album.indices { album[i].year = "2024" }
        let single = Track(title: "Single", artist: "Singer", album: "A Single", filename: "single.wav", duration: 180)
        let feature = Track(title: "Guest", artist: "Other,Singer", album: "Other's Album", albumArtist: "Other", filename: "guest.wav", duration: 200)
        let catalog = ArtistCatalog.build(album + [single, feature], artist: "Singer", separators: ",")
        XCTAssertEqual(catalog.albums.count, 1); XCTAssertEqual(catalog.albums[0].count, 7)
        XCTAssertEqual(catalog.singles[0][0].id, single.id)
        XCTAssertEqual(catalog.featured[0][0].id, feature.id)
        XCTAssertEqual(catalog.songs.count, 8)
    }
    func testTTMLAppleMetadataDuetsAndSecondsAreAbsolute() {
        let xml = #"<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" xmlns:itunes="http://music.apple.com/lyric-ttml-internal"><head><metadata><translations><text for="L1">你好</text></translations><transliterations><text for="L1">ni hao</text></transliterations></metadata></head><body><div><p begin="1s" end="4s" itunes:key="L1" ttm:agent="v1"><span begin="1s" end="2s">Hello</span></p><p begin="1s" end="3s" ttm:agent="v2">World</p><p begin="7s" end="8s">End</p></div></body></tt>"#
        let lines = LyricsParser.parse(xml)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].words[0].start, 1)
        XCTAssertEqual(lines[0].translation, "你好")
        XCTAssertEqual(lines[0].transliteration, "ni hao")
        XCTAssertEqual(lines[1].agent, "v2")
        XCTAssertEqual(LyricsParser.activeIndices(in: lines, at: 2), [0, 1])
        XCTAssertEqual(LyricsParser.activeIndices(in: lines, at: 5), [])
        XCTAssertEqual(LyricsParser.parse("[00:01]v2:Duet")[0].agent, "v2")
    }
    func testLyricSourcePriorityAndManualOverride() {
        let xml = #"<tt><body><p begin="1s" end="3s">Embedded TTML</p></body></tt>"#
        let lrc = "[00:01]External LRC"
        XCTAssertEqual(LyricsParser.preferred(embedded: xml, sidecar: lrc).first?.text, "Embedded TTML")
        XCTAssertEqual(LyricsParser.preferred(embedded: lrc, sidecar: xml).first?.text, "Embedded TTML")
        XCTAssertEqual(LyricsParser.preferred(embedded: "<tt><broken>", sidecar: lrc).first?.text, "External LRC")
        XCTAssertEqual(LyricsParser.preferred(embedded: xml, sidecar: lrc, manual: true).first?.text, "External LRC")
    }
    func testQueueReorderRoundTripAndMoveNext() throws {
        let ids = (0..<5).map { _ in UUID() }
        var queue = PlaybackQueue(); queue.replace(with: ids, startingAt: 2)
        let current = queue.current
        queue.moveNext(queue.entries[0].id)
        XCTAssertEqual(queue.current, current)
        XCTAssertEqual(queue.upcoming.first?.trackID, ids[0])
        queue.move(from: IndexSet(integer: 4), to: 0)
        XCTAssertEqual(queue.current, current)
        let restored = try JSONDecoder().decode(PlaybackQueue.self, from: JSONEncoder().encode(queue))
        XCTAssertEqual(restored.entries, queue.entries)
        XCTAssertEqual(restored.current, current)
        queue.clearUpcoming(); XCTAssertTrue(queue.upcoming.isEmpty)
    }
    func testRequestedQueueIsFIFOAndSurvivesShuffleAndClear() throws {
        let ids = (0..<6).map { _ in UUID() }
        var queue = PlaybackQueue(); queue.replace(with: Array(ids.prefix(3)))
        queue.insert([ids[3], ids[4]], next: true)
        XCTAssertEqual(queue.nextInQueue.map(\.trackID), [ids[3], ids[4]])
        XCTAssertEqual(queue.upNext.map(\.trackID), [ids[1], ids[2]])
        queue.toggleShuffle(); queue.toggleShuffle()
        XCTAssertEqual(queue.nextInQueue.map(\.trackID), [ids[3], ids[4]])
        queue.moveNext(queue.upNext.last!.id)
        XCTAssertEqual(queue.nextInQueue.map(\.trackID), [ids[3], ids[4], ids[2]])
        let restored = try JSONDecoder().decode(PlaybackQueue.self, from: JSONEncoder().encode(queue))
        XCTAssertEqual(restored.nextInQueue, queue.nextInQueue)
        queue.clearNextInQueue()
        XCTAssertTrue(queue.nextInQueue.isEmpty); XCTAssertEqual(queue.upNext.map(\.trackID), [ids[1]])
    }
    func testShufflePreservesCurrentAndRestoresOrder() {
        let ids = (0..<20).map { _ in UUID() }
        var queue = PlaybackQueue(); queue.replace(with: ids, startingAt: 5)
        let current = queue.current
        queue.toggleShuffle()
        XCTAssertEqual(queue.current, current)
        XCTAssertEqual(Set(queue.entries.map(\.trackID)), Set(ids))
        XCTAssertEqual(Array(queue.entries.prefix(6).map(\.trackID)), Array(ids.prefix(6)))
        queue.toggleShuffle()
        XCTAssertEqual(queue.entries.map(\.trackID), ids)
        XCTAssertEqual(queue.current, current)
    }
    func testQueueDuplicateTracksAndSafeRemoval() {
        let id = UUID()
        var queue = PlaybackQueue(); queue.replace(with: [id, id])
        XCTAssertNotEqual(queue.entries[0].id, queue.entries[1].id)
        let currentID = queue.current!.id
        queue.remove(currentID)
        XCTAssertEqual(queue.entries.count, 2)
        queue.insert(UUID(), next: true)
        XCTAssertEqual(queue.upcoming.count, 2)
        queue.remove(queue.upcoming[0].id)
        XCTAssertEqual(queue.current?.id, currentID)
        queue.replace(with: [], startingAt: 99)
        XCTAssertNil(queue.current); XCTAssertFalse(queue.advance()); XCTAssertFalse(queue.previous())
    }
    func testStartingShuffleRetainsEverySongInUpcomingQueue() {
        let ids = (0..<10).map { _ in UUID() }
        var queue = PlaybackQueue()
        queue.replace(with: ids, startingAt: 7, shuffled: true)
        XCTAssertEqual(queue.current?.trackID, ids[7])
        XCTAssertEqual(queue.upcoming.count, 9)
        XCTAssertEqual(Set(queue.upcoming.map(\.trackID)), Set(ids.filter { $0 != ids[7] }))
        queue.toggleShuffle()
        XCTAssertEqual(queue.entries.map(\.trackID), ids)
        XCTAssertEqual(queue.current?.trackID, ids[7])
    }
    func testDeletingTrackPreservesSurvivingQueueAndRemovesDuplicates() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        var queue = PlaybackQueue()
        queue.replace(with: [a, b, a, c, d], startingAt: 1)
        let currentEntry = queue.current?.id
        queue.removeTrack(a)
        XCTAssertEqual(queue.entries.map(\.trackID), [b, c, d])
        XCTAssertEqual(queue.current?.id, currentEntry)
        queue.removeTrack(b)
        XCTAssertEqual(queue.current?.trackID, c)
        queue.removeTrack(d)
        queue.removeTrack(c)
        XCTAssertTrue(queue.entries.isEmpty)
        XCTAssertNil(queue.current)
    }
    func testLegacyHistoryIsIgnoredWithoutLosingLibrary() throws {
        var original = LibrarySnapshot()
        let track = Track(title: "歌曲", filename: "track.flac", isFavorite: true)
        original.tracks = [track]
        original.playlists = [.init(name: "我的歌单", trackIDs: [track.id])]
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        legacy["sessions"] = [["obsolete": "ignored without decoding statistics"]]
        var tracks = try XCTUnwrap(legacy["tracks"] as? [[String: Any]])
        tracks[0]["lastPlayedAt"] = 12345.0
        legacy["tracks"] = tracks
        let decoded = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.tracks, original.tracks)
        XCTAssertEqual(decoded.playlists, original.playlists)
        let rewritten = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        XCTAssertNil(rewritten["sessions"])
        let rewrittenTracks = try XCTUnwrap(rewritten["tracks"] as? [[String: Any]])
        XCTAssertNil(rewrittenTracks[0]["lastPlayedAt"])
    }
    func testLibraryRoundTripAndLabels() throws {
        var snapshot = LibrarySnapshot()
        let track = Track(title: "歌曲", artist: "艺人", album: "专辑", filename: "track.flac", isFavorite: true)
        snapshot.tracks = [track]
        snapshot.playlists = [.init(name: "我的歌单", trackIDs: [track.id])]
        let decoded = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.tracks, [track])
        XCTAssertEqual(decoded.playlists[0].trackIDs, [track.id])
        XCTAssertTrue(track.isLossless); XCTAssertTrue(track.matches("歌曲")); XCTAssertFalse(track.matches("missing"))
        XCTAssertEqual(PlaybackTime.label(-10), "0:00")
        XCTAssertEqual(PlaybackTime.label(.infinity), "0:00")
        XCTAssertEqual(PlaybackTime.label(125.8), "2:05")
        XCTAssertFalse(PlaybackTime.label(.greatestFiniteMagnitude).isEmpty)
    }
}
