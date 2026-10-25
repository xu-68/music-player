import Foundation

public struct RecentMusic: Identifiable, Sendable {
    public var tracks: [Track]
    public var isAlbum: Bool
    public var id: UUID { tracks[0].id }
    public static func group(_ recent: [Track], limit: Int = 10) -> [RecentMusic] {
        var result: [RecentMusic] = [], index = 0
        while index < recent.count && result.count < limit {
            var end = index + 1
            while end < recent.count && recent[end].album == recent[index].album { end += 1 }
            if end - index >= 4 { result.append(.init(tracks: Array(recent[index..<end]), isAlbum: true)) }
            else { for track in recent[index..<end] where result.count < limit { result.append(.init(tracks: [track], isAlbum: false)) } }
            index = end
        }
        return result
    }
}
