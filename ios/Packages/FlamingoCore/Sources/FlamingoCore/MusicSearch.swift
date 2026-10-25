import Foundation

public enum MusicSearch {
    public static func ranked(_ tracks: [Track], query: String) -> [Track] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return tracks }
        let budget = q.count <= 4 ? 1 : q.count <= 8 ? 2 : 3
        return tracks.enumerated().compactMap { index, track -> (Track, Int, Int)? in
            let fields = [track.title, track.artist, track.album, track.albumArtist, track.genre ?? "", track.composer ?? "", track.writer ?? "", track.author ?? "", track.year ?? ""].map { $0.lowercased() }
            let title = fields[0]
            if title == q { return (track, 0, index) }
            if title.hasPrefix(q) { return (track, 10, index) }
            if let range = title.range(of: q) { return (track, 20 + title.distance(from: title.startIndex, to: range.lowerBound), index) }
            for i in 1..<fields.count where fields[i].contains(q) { return (track, (i < 4 ? 100 : 200) + i * 10, index) }
            for (i, field) in fields.enumerated() {
                if let distance = substringDistance(Array(field), Array(q), budget: budget) { return (track, 1000 + i * 100 + distance * 10, index) }
            }
            return nil
        }.sorted { $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 < $1.1 }.map { $0.0 }
    }
    // Free prefix/suffix in the field; bounded edit distance within a substring.
    private static func substringDistance(_ field: [Character], _ query: [Character], budget: Int) -> Int? {
        guard !field.isEmpty, field.count + budget >= query.count else { return nil }
        var previous = [Int](repeating: 0, count: field.count + 1)
        for i in query.indices {
            var row = [Int](repeating: 0, count: field.count + 1); row[0] = i + 1
            for j in field.indices {
                row[j + 1] = min(previous[j + 1] + 1, row[j] + 1, previous[j] + (query[i] == field[j] ? 0 : 1))
            }
            previous = row
        }
        let best = previous.min() ?? budget + 1
        return best <= budget ? best : nil
    }
}
