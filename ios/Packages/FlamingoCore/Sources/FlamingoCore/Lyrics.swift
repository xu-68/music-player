import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct LyricWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double?
    public init(text: String, start: Double, end: Double? = nil) {
        self.text = text; self.start = start; self.end = end
    }
}

public struct LyricLine: Identifiable, Equatable, Sendable {
    public var id: Int
    public var start: Double
    public var end: Double?
    public var text: String
    public var translation: String?
    public var words: [LyricWord]
    public var transliteration: String?
    public var agent: String?
    public var key: String?
    public init(id: Int, start: Double, end: Double? = nil, text: String,
                translation: String? = nil, words: [LyricWord] = []) {
        self.id = id; self.start = start; self.end = end; self.text = text
        self.translation = translation; self.words = words
    }
}

public enum LyricsParser {
    public static func parse(_ text: String) -> [LyricLine] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<") || trimmed.hasPrefix("\u{feff}<") {
            let delegate = TTMLReader()
            let parser = XMLParser(data: Data(trimmed.utf8))
            parser.shouldProcessNamespaces = true
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            guard parser.parse() else { return [] }
            return normalize(delegate.result(), mergeTranslations: false)
        }
        return parseLRC(text)
    }

    public static func activeIndex(in lines: [LyricLine], at time: Double) -> Int? {
        guard time.isFinite, let first = lines.first, time >= first.start else { return nil }
        var low = 0, high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        return low - 1
    }

    public static func activeIndices(in lines: [LyricLine], at time: Double) -> Set<Int> {
        guard time.isFinite else { return [] }
        return Set(lines.indices.filter { lines[$0].start <= time && time < (lines[$0].end ?? .infinity) })
    }

    private static func parseLRC(_ source: String) -> [LyricLine] {
        let stamp = try! NSRegularExpression(pattern: #"[\[<](\d+):(\d{1,2}(?:\.\d+)?)[\]>]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let ns = source as NSString
        let offset = offsetPattern.firstMatch(in: source, range: NSRange(location: 0, length: ns.length))
            .flatMap { Double(ns.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
        var result: [LyricLine] = []
        for raw in source.components(separatedBy: .newlines) {
            let line = raw as NSString
            let matches = stamp.matches(in: raw, range: NSRange(location: 0, length: line.length))
            guard let first = matches.first, first.range.location == 0 else { continue }
            func time(_ match: NSTextCheckingResult) -> Double {
                (Double(line.substring(with: match.range(at: 1))) ?? 0) * 60 +
                    (Double(line.substring(with: match.range(at: 2))) ?? 0) + offset
            }
            let hasInlineWords = matches.dropFirst().contains { match in
                let prefix = line.substring(to: match.range.location)
                return stamp.stringByReplacingMatches(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length), withTemplate: "")
                    .trimmingCharacters(in: .whitespaces).isEmpty == false
            }
            if hasInlineWords {
                var words: [LyricWord] = []
                for (i, match) in matches.enumerated() {
                    let start = NSMaxRange(match.range)
                    let stop = i + 1 < matches.count ? matches[i + 1].range.location : line.length
                    let text = line.substring(with: NSRange(location: start, length: stop - start))
                    if !text.isEmpty {
                        words.append(.init(text: text, start: max(0, time(match)),
                                           end: i + 1 < matches.count ? max(0, time(matches[i + 1])) : nil))
                    }
                }
                result.append(.init(id: result.count, start: max(0, time(first)), text: words.map(\.text).joined(), words: words))
            } else {
                let text = line.substring(from: NSMaxRange(matches.last!.range)).trimmingCharacters(in: .whitespaces)
                for match in matches { result.append(.init(id: result.count, start: max(0, time(match)), text: text)) }
            }
        }
        for i in result.indices {
            for agent in ["v1", "v2"] where result[i].text.hasPrefix(agent + ":") {
                result[i].agent = agent
                result[i].text = String(result[i].text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if !result[i].words.isEmpty {
                    result[i].words[0].text = result[i].words[0].text.replacingOccurrences(of: agent + ":", with: "")
                }
            }
        }
        return normalize(result, mergeTranslations: true)
    }

    private static func normalize(_ input: [LyricLine], mergeTranslations: Bool) -> [LyricLine] {
        let sorted = input.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        var result: [LyricLine] = []
        for line in sorted {
            if mergeTranslations, let last = result.last, abs(last.start - line.start) < 0.001,
               !last.text.isEmpty, !line.text.isEmpty, last.text != line.text {
                result[result.count - 1].translation = line.text
            } else { result.append(line) }
        }
        for i in result.indices {
            result[i].id = i
            if result[i].end == nil { result[i].end = result.dropFirst(i + 1).first { $0.start > result[i].start }?.start }
            for j in result[i].words.indices where result[i].words[j].end == nil {
                result[i].words[j].end = j + 1 < result[i].words.count ? result[i].words[j + 1].start : result[i].end
            }
        }
        return result
    }
}

private final class TTMLReader: NSObject, XMLParserDelegate {
    struct Node {
        var name: String
        var begin: Double
        var end: Double?
        var text = ""
        var role: String
        var words: [LyricWord] = []
        var translation = ""
        var transliteration = ""
        var agent: String?
        var key: String?
        var reference: String?
    }
    var lines: [LyricLine] = []
    var stack: [Node] = []
    var frameRate: Double = 30
    var tickRate: Double = 1
    var translations: [String: String] = [:]
    var transliterations: [String: String] = [:]

    func result() -> [LyricLine] {
        lines.map { line in
            var value = line
            if let key = line.key {
                value.translation = translations[key] ?? line.translation
                value.transliteration = transliterations[key] ?? line.transliteration
            }
            return value
        }
    }

    func seconds(_ value: String) -> Double? {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        if parts.count == 4 { return parts[0] * 3600 + parts[1] * 60 + parts[2] + parts[3] / frameRate }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        for (suffix, factor) in [("ms", 0.001), ("h", 3600.0), ("m", 60.0), ("s", 1.0), ("f", 1 / frameRate), ("t", 1 / tickRate)] {
            if value.hasSuffix(suffix) { return Double(value.dropLast(suffix.count)).map { $0 * factor } }
        }
        return Double(value)
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributes: [String: String]) {
        func attribute(_ name: String) -> String? {
            attributes.first { $0.key.split(separator: ":").last.map(String.init) == name }?.value
        }
        if elementName == "tt" {
            frameRate = max(1, Double(attribute("frameRate") ?? "30") ?? 30)
            tickRate = max(1, Double(attribute("tickRate") ?? "1") ?? 1)
        }
        if elementName == "br" { if !stack.isEmpty { stack[stack.count - 1].text += "\n" }; return }
        let parentBegin = stack.last?.begin ?? 0
        func absolute(_ string: String?) -> Double? {
            guard let string, let value = seconds(string) else { return nil }
            // Flamingo/Apple music documents use absolute timestamps for p/span,
            // including decimal seconds with an s suffix.
            return value
        }
        let begin = absolute(attribute("begin")) ?? parentBegin
        let end = absolute(attribute("end")) ?? attribute("dur").flatMap(seconds).map { begin + $0 } ?? stack.last?.end
        var node = Node(name: elementName, begin: begin, end: end, role: attribute("role") ?? "")
        node.agent = attribute("agent"); node.key = attribute("key"); node.reference = attribute("for")
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !stack.isEmpty { stack[stack.count - 1].text += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "br" { return }
        guard let node = stack.popLast() else { return }
        let translation = node.role.contains("translation")
        let transliteration = node.role.contains("transliteration")
        if elementName == "text", let key = node.reference {
            if stack.contains(where: { $0.name == "transliterations" }) { transliterations[key] = node.text }
            else if stack.contains(where: { $0.name == "translations" }) { translations[key] = node.text }
        }
        if elementName == "p", stack.contains(where: { $0.name == "body" }) {
            let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var line = LyricLine(id: lines.count, start: node.begin, end: node.end ?? node.words.last?.end, text: text,
                                 translation: node.translation.isEmpty ? nil : node.translation, words: node.words)
            line.transliteration = node.transliteration.isEmpty ? nil : node.transliteration
            line.agent = node.agent; line.key = node.key
            lines.append(line)
        } else if !stack.isEmpty {
            let i = stack.count - 1
            if transliteration { stack[i].transliteration += node.text }
            else if translation { stack[i].translation += node.text }
            else {
                stack[i].text += node.text
                if elementName == "span", node.words.isEmpty, !node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    stack[i].words.append(.init(text: node.text, start: node.begin, end: node.end))
                } else { stack[i].words += node.words }
                stack[i].translation += node.translation
                stack[i].transliteration += node.transliteration
            }
        }
    }
}
