import Foundation

public struct Track: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var filename: String
    public var artworkFilename: String?
    public var lyricsFilename: String?
    public var manualLyrics: Bool?
    public var embeddedLyrics: String?
    public var duration: Double
    public var trackNumber: Int
    public var discNumber: Int
    public var addedAt: Date
    public var isFavorite: Bool
    public var lastPlayedAt: Date?
    public var originalFilename: String?
    public var modifiedAt: Date?
    public var sourceFolderID: UUID?
    public var sourceDirectory: String?
    public var videoFilename: String?
    public var decodedFilename: String?
    public var codec: String?
    public var sampleRate: Double?
    public var bitsPerSample: Int?
    public var bitRate: Int?
    public var genre: String?
    public var composer: String?
    public var writer: String?
    public var author: String?
    public var year: String?

    public init(id: UUID = UUID(), title: String, artist: String = "未知艺人",
                album: String = "未知专辑", albumArtist: String = "", filename: String,
                artworkFilename: String? = nil, lyricsFilename: String? = nil,
                embeddedLyrics: String? = nil, duration: Double = 0,
                trackNumber: Int = 0, discNumber: Int = 0, addedAt: Date = Date(),
                isFavorite: Bool = false, lastPlayedAt: Date? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.album = album
        self.albumArtist = albumArtist; self.filename = filename
        self.artworkFilename = artworkFilename; self.lyricsFilename = lyricsFilename
        self.embeddedLyrics = embeddedLyrics; self.duration = duration
        self.trackNumber = trackNumber; self.discNumber = discNumber
        self.addedAt = addedAt; self.isFavorite = isFavorite; self.lastPlayedAt = lastPlayedAt
    }

    public var albumKey: String { "\(albumArtist.isEmpty ? artist : albumArtist)\u{1f}\(album)" }
    public var isLossless: Bool {
        ["flac", "wav", "aiff", "aif", "ape", "wv", "tta", "tak"].contains((filename as NSString).pathExtension.lowercased()) || codec?.lowercased() == "alac"
    }
    public func matches(_ query: String) -> Bool {
        query.isEmpty || [title, artist, album, albumArtist, genre ?? "", composer ?? "", writer ?? "", author ?? "", year ?? ""].contains { $0.localizedStandardContains(query) }
    }
}

public struct Playlist: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var trackIDs: [UUID]
    public var description: String?
    public var artworkFilename: String?
    public var isPinned: Bool?
    public var pinOrder: Int?
    public init(id: UUID = UUID(), name: String, trackIDs: [UUID] = []) {
        self.id = id; self.name = name; self.trackIDs = trackIDs
    }
}

public struct ListeningSession: Codable, Identifiable, Sendable {
    public var id: UUID
    public var trackID: UUID
    public var date: Date
    public var seconds: Double
    public var title: String?
    public var artist: String?
    public var album: String?
    public var originalURI: String?
    public var countsAsPlay: Bool?
    public var dayStart: Date?
    public var isImported: Bool?
    public init(trackID: UUID, date: Date = Date(), seconds: Double) {
        self.id = UUID(); self.trackID = trackID; self.date = date; self.seconds = seconds
    }
}

public struct LibrarySnapshot: Codable, Sendable {
    public var version: Int = 1
    public var tracks: [Track] = []
    public var playlists: [Playlist] = []
    public var sessions: [ListeningSession] = []
    public var followedArtists: [String] = []
    public var folders: [MusicFolder] = []
    public var hiddenDirectories: [String] = []
    public init() {}
    enum CodingKeys: String, CodingKey { case version, tracks, playlists, sessions, followedArtists, folders, hiddenDirectories }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        version = try box.decodeIfPresent(Int.self, forKey: .version) ?? 1
        tracks = try box.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        playlists = try box.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
        sessions = try box.decodeIfPresent([ListeningSession].self, forKey: .sessions) ?? []
        followedArtists = try box.decodeIfPresent([String].self, forKey: .followedArtists) ?? []
        folders = try box.decodeIfPresent([MusicFolder].self, forKey: .folders) ?? []
        hiddenDirectories = try box.decodeIfPresent([String].self, forKey: .hiddenDirectories) ?? []
    }
}

public struct MusicFolder: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var bookmark: Data
    public init(name: String, bookmark: Data) { id = UUID(); self.name = name; self.bookmark = bookmark }
}

public enum SongSort: String, CaseIterable, Sendable {
    case title = "标题", duration = "时长", artist = "艺人", modified = "修改日期"
    public func sorted(_ tracks: [Track], descending: Bool) -> [Track] {
        let sorted = tracks.sorted { a, b in
            switch self {
            case .title: return a.title.localizedStandardCompare(b.title) == .orderedAscending
            case .duration: return a.duration == b.duration ? a.title < b.title : a.duration < b.duration
            case .artist: return a.artist == b.artist ? a.title < b.title : a.artist.localizedStandardCompare(b.artist) == .orderedAscending
            case .modified: return (a.modifiedAt ?? a.addedAt) < (b.modifiedAt ?? b.addedAt)
            }
        }
        return descending ? Array(sorted.reversed()) : sorted
    }
}

public enum SleepMode: String, Codable, CaseIterable, Sendable {
    case duration = "倒计时", endOfTrack = "本首结束", endOfQueue = "队列结束"
}

public struct SleepPlan: Codable, Equatable, Sendable {
    public var mode: SleepMode
    public var deadline: Date?
    public var fadeSeconds: Double
    public init(mode: SleepMode, minutes: Double = 30, fadeSeconds: Double = 5, now: Date = Date()) {
        self.mode = mode; self.deadline = mode == .duration ? now.addingTimeInterval(max(1, minutes * 60)) : nil
        self.fadeSeconds = max(0, fadeSeconds)
    }
}

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one
    public var next: Self { switch self { case .off: return .all; case .all: return .one; case .one: return .off } }
}

public struct QueueEntry: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var trackID: UUID
    public var requested: Bool?
    public init(trackID: UUID) { self.id = UUID(); self.trackID = trackID }
}

public struct PlaybackQueue: Codable, Sendable {
    public private(set) var entries: [QueueEntry] = []
    public private(set) var index: Int = 0
    public private(set) var shuffled = false
    public var repeatMode: RepeatMode = .off
    private var originalOrder: [UUID] = []
    public init() {}
    public var current: QueueEntry? { entries.indices.contains(index) ? entries[index] : nil }
    public var upcoming: [QueueEntry] { Array(entries.dropFirst(index + 1)) }
    public var nextInQueue: [QueueEntry] { Array(upcoming.prefix { $0.requested == true }) }
    public var upNext: [QueueEntry] { Array(upcoming.dropFirst(nextInQueue.count)) }

    public mutating func replace(with ids: [UUID], startingAt offset: Int = 0, shuffled: Bool = false) {
        entries = ids.map(QueueEntry.init)
        index = entries.isEmpty ? 0 : min(max(0, offset), entries.count - 1)
        originalOrder = entries.map(\.id)
        self.shuffled = shuffled
        if shuffled, let selected = current {
            entries = [selected] + entries.filter { $0.id != selected.id }.shuffled()
            index = 0
        }
    }

    @discardableResult public mutating func advance(automatic: Bool = false) -> Bool {
        guard current != nil else { return false }
        if automatic && repeatMode == .one { return true }
        if index + 1 < entries.count { index += 1; entries[index].requested = false; return true }
        if repeatMode == .all { index = 0; return true }
        return false
    }
    @discardableResult public mutating func previous() -> Bool {
        guard current != nil else { return false }
        if index > 0 { index -= 1; return true }
        if repeatMode == .all { index = entries.count - 1; return true }
        return false
    }
    public mutating func select(_ entryID: UUID) {
        if let i = entries.firstIndex(where: { $0.id == entryID }) {
            index = i
            for consumed in 0...i where entries[consumed].requested == true { entries[consumed].requested = false }
        }
    }
    public mutating func move(from offsets: IndexSet, to destination: Int) {
        guard let currentID = current?.id else { return }
        let valid = offsets.filter { entries.indices.contains($0) }
        let moving = valid.map { entries[$0] }
        let adjustment = valid.filter { $0 < destination }.count
        for i in valid.reversed() { entries.remove(at: i) }
        entries.insert(contentsOf: moving, at: min(max(0, destination - adjustment), entries.count))
        originalOrder = entries.map(\.id)
        index = entries.firstIndex { $0.id == currentID } ?? 0
    }
    public mutating func moveNext(_ id: UUID) {
        guard let from = entries.firstIndex(where: { $0.id == id }), from != index else { return }
        guard !nextInQueue.contains(where: { $0.id == id }) else { return }
        let destination = index + 1 + nextInQueue.count
        entries[from].requested = true
        move(from: IndexSet(integer: from), to: destination)
    }
    public mutating func clearNextInQueue() {
        let ids = Set(nextInQueue.map(\.id))
        entries.removeAll { ids.contains($0.id) }; originalOrder.removeAll { ids.contains($0) }
    }
    public mutating func clearUpcoming() {
        entries = Array(entries.prefix(index + 1))
        let retained = Set(entries.map(\.id)); originalOrder.removeAll { !retained.contains($0) }
    }
    public mutating func insert(_ trackID: UUID, next: Bool) {
        insert([trackID], next: next)
    }
    public mutating func insert(_ trackIDs: [UUID], next: Bool) {
        let additions = trackIDs.map { id -> QueueEntry in var entry = QueueEntry(trackID: id); entry.requested = next; return entry }
        guard !additions.isEmpty else { return }
        let offset = next && !entries.isEmpty ? index + 1 + nextInQueue.count : entries.count
        let anchor = offset > 0 ? entries[offset - 1].id : nil
        entries.insert(contentsOf: additions, at: offset)
        if next, let anchor, let rank = originalOrder.firstIndex(of: anchor) {
            originalOrder.insert(contentsOf: additions.map(\.id), at: rank + 1)
        } else { originalOrder.append(contentsOf: additions.map(\.id)) }
    }
    public mutating func remove(_ entryID: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == entryID }), i != index else { return }
        entries.remove(at: i); originalOrder.removeAll { $0 == entryID }
        if i < index { index -= 1 }
    }
    public mutating func removeTrack(_ trackID: UUID) {
        let survivingCurrent = current.flatMap { $0.trackID == trackID ? nil : $0.id }
        let removedBeforeCurrent = entries.prefix(index).filter { $0.trackID == trackID }.count
        let removedIDs = Set(entries.filter { $0.trackID == trackID }.map(\.id))
        entries.removeAll { $0.trackID == trackID }
        originalOrder.removeAll { removedIDs.contains($0) }
        if let survivingCurrent, let currentIndex = entries.firstIndex(where: { $0.id == survivingCurrent }) {
            index = currentIndex
        } else { index = min(max(0, index - removedBeforeCurrent), max(0, entries.count - 1)) }
    }
    public mutating func toggleShuffle() {
        guard let currentID = current?.id else { return }
        shuffled.toggle()
        if shuffled {
            let requested = nextInQueue
            let tail = upNext.shuffled()
            entries = Array(entries.prefix(index + 1)) + requested + tail
        } else {
            let requested = nextInQueue
            let ids = Set(requested.map(\.id))
            entries.removeAll { ids.contains($0.id) }
            let rank = Dictionary(uniqueKeysWithValues: originalOrder.enumerated().map { ($1, $0) })
            entries.sort { rank[$0.id, default: 0] < rank[$1.id, default: 0] }
            index = entries.firstIndex { $0.id == currentID } ?? 0
            entries.insert(contentsOf: requested, at: min(index + 1, entries.count))
        }
    }
}

public enum PlaybackTime {
    public static func label(_ seconds: Double) -> String {
        let bounded = seconds.isFinite ? min(max(0, seconds), 31_557_600_000) : 0
        let value = Int(bounded.rounded(.down))
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }
}
