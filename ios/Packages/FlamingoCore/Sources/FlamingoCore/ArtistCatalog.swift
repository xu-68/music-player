import Foundation

public struct ArtistCatalog: Sendable {
    public var songs: [Track]
    public var albums: [[Track]]
    public var singles: [[Track]]
    public var featured: [[Track]]
    public static func build(_ tracks: [Track], artist: String, separators: String) -> ArtistCatalog {
        func split(_ value: String) -> [String] { value.components(separatedBy: CharacterSet(charactersIn: separators)).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        let all = tracks.filter { split($0.artist).contains(artist) || split($0.albumArtist).contains(artist) }
        let primary = all.filter { $0.albumArtist.isEmpty ? split($0.artist).first == artist : split($0.albumArtist).contains(artist) }
        let songs = primary.isEmpty ? all : primary
        func releases(_ songs: [Track]) -> [[Track]] {
            Dictionary(grouping: songs, by: \.albumKey).values.map { $0.sorted { ($0.discNumber, $0.trackNumber, $0.title) < ($1.discNumber, $1.trackNumber, $1.title) } }.sorted {
                let a = $0.compactMap { Int(($0.year ?? "").prefix(4)) }.max() ?? Int.min
                let b = $1.compactMap { Int(($0.year ?? "").prefix(4)) }.max() ?? Int.min
                return a == b ? $0[0].album < $1[0].album : a > b
            }
        }
        let main = releases(songs), keys = Set(main.compactMap { $0.first?.albumKey })
        func single(_ release: [Track]) -> Bool {
            let name = release.first?.album.lowercased() ?? ""
            return [" - single", " (single)", " [single]", " - ep", " (ep)", " [ep]"].contains { name.contains($0) } || release.count <= 6 && release.reduce(0) { $0 + $1.duration } <= 2100
        }
        let ordered = songs.sorted {
            let a = Int(($0.year ?? "").prefix(4)) ?? Int.min, b = Int(($1.year ?? "").prefix(4)) ?? Int.min
            return a == b ? ($0.album, $0.discNumber, $0.trackNumber, $0.title) < ($1.album, $1.discNumber, $1.trackNumber, $1.title) : a > b
        }
        return .init(songs: ordered, albums: main.filter { !single($0) }, singles: main.filter(single), featured: releases(all.filter { !keys.contains($0.albumKey) }))
    }
}
