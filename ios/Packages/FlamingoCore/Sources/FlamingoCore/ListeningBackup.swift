import Foundation

/// Matches the Android ListenStatsEvent JSON, so backups remain portable.
public struct ListeningEvent: Codable, Sendable {
    public var uri: String?
    public var title: String
    public var artists: String
    public var album: String
    public var albumArtists: String
    public var dayStartMs: Int64
    public var timestampMs: Int64
    public var listenedMs: Int64
    public var countsAsPlay: Bool
    enum CodingKeys: String, CodingKey { case uri, title, artists, album, albumArtists, dayStartMs, timestampMs, listenedMs, countsAsPlay }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        uri = try box.decodeIfPresent(String.self, forKey: .uri)
        title = try box.decodeIfPresent(String.self, forKey: .title) ?? "未知歌曲"
        artists = try box.decodeIfPresent(String.self, forKey: .artists) ?? "未知艺人"
        album = try box.decodeIfPresent(String.self, forKey: .album) ?? "未知专辑"
        albumArtists = try box.decodeIfPresent(String.self, forKey: .albumArtists) ?? ""
        dayStartMs = try box.decodeIfPresent(Int64.self, forKey: .dayStartMs) ?? 0
        timestampMs = try box.decodeIfPresent(Int64.self, forKey: .timestampMs) ?? 0
        listenedMs = try box.decodeIfPresent(Int64.self, forKey: .listenedMs) ?? 0
        countsAsPlay = try box.decodeIfPresent(Bool.self, forKey: .countsAsPlay) ?? false
    }
    public init(session: ListeningSession, track: Track?) {
        uri = session.isImported == true ? session.originalURI : session.originalURI ?? "flamingo://track/\(session.trackID.uuidString)"
        title = session.title ?? track?.title ?? "已移除的歌曲"
        artists = session.artist ?? track?.artist ?? "未知艺人"
        album = session.album ?? track?.album ?? "未知专辑"
        albumArtists = track?.albumArtist ?? ""
        dayStartMs = Int64(((session.dayStart ?? Calendar.current.startOfDay(for: session.date)).timeIntervalSince1970 * 1000).rounded())
        timestampMs = Int64((session.date.timeIntervalSince1970 * 1000).rounded())
        listenedMs = Int64(min(max(0, session.seconds * 1000), Double(Int64.max / 2)))
        countsAsPlay = session.countsAsPlay ?? false
    }
    public var identity: String { "\(uri ?? "")|\(timestampMs)|\(dayStartMs)" }
    public func session(trackID: UUID) -> ListeningSession {
        var value = ListeningSession(trackID: trackID, date: Date(timeIntervalSince1970: Double(timestampMs) / 1000), seconds: Double(max(0, listenedMs)) / 1000)
        value.title = title; value.artist = artists; value.album = album
        value.originalURI = uri; value.countsAsPlay = countsAsPlay
        value.dayStart = Date(timeIntervalSince1970: Double(dayStartMs) / 1000)
        value.isImported = true
        return value
    }
}

public enum ListeningBackup {
    public static func export(_ sessions: [ListeningSession], tracks: [Track]) throws -> Data {
        let lookup = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(sessions.map { ListeningEvent(session: $0, track: lookup[$0.trackID]) })
    }
    public static func restore(_ data: Data, into existing: [ListeningSession], tracks: [Track], merge: Bool) throws -> [ListeningSession] {
        let events = try JSONDecoder().decode([ListeningEvent].self, from: data)
        var result = merge ? existing : []
        var seen = Set(result.map { ListeningEvent(session: $0, track: nil).identity })
        var orphanIDs: [String: UUID] = [:]
        for session in result { if let uri = session.originalURI { orphanIDs[uri] = session.trackID } }
        for event in events where event.listenedMs >= 0 && event.timestampMs >= 0 {
            guard seen.insert(event.identity).inserted else { continue }
            let uriID = event.uri.flatMap { URL(string: $0)?.lastPathComponent }.flatMap(UUID.init(uuidString:))
            let match = tracks.first { $0.id == uriID || ($0.title == event.title && $0.artist == event.artists && $0.album == event.album) }
            let key = event.uri ?? "\(event.title)|\(event.artists)|\(event.album)"
            let id = match?.id ?? orphanIDs[key] ?? UUID()
            orphanIDs[key] = id
            result.append(event.session(trackID: id))
        }
        return result.sorted { $0.date < $1.date }
    }
}
