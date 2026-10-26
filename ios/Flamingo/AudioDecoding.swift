import AVFoundation
import FlamingoDecoder
import Foundation

enum NativeDecoder {
    static func probe(_ input: URL, cover: URL) throws -> [String: String] {
        let metadata = URL.temporaryDirectory.appending(path: UUID().uuidString + ".plist")
        defer { try? FileManager.default.removeItem(at: metadata) }
        var message = [CChar](repeating: 0, count: 512)
        let status = flamingo_probe(input.path, metadata.path, cover.path, &message, Int32(message.count))
        guard status >= 0 else {
            throw NSError(domain: "FlamingoDecoder", code: Int(status), userInfo: [NSLocalizedDescriptionKey: String(cString: message)])
        }
        return try readTags(metadata)
    }

    static func decode(_ input: URL, output: URL) throws -> [String: String] {
        let metadata = output.appendingPathExtension("plist")
        let cover = output.appendingPathExtension("cover")
        var message = [CChar](repeating: 0, count: 512)
        let status = flamingo_decode(input.path, output.path, metadata.path, cover.path, &message, Int32(message.count))
        guard status >= 0 else {
            throw NSError(domain: "FlamingoDecoder", code: Int(status), userInfo: [NSLocalizedDescriptionKey: String(cString: message)])
        }
        defer { try? FileManager.default.removeItem(at: metadata) }
        return try readTags(metadata)
    }

    private static func readTags(_ metadata: URL) throws -> [String: String] {
        let data = try Data(contentsOf: metadata)
        let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] ?? [:]
        var normalized = value
        for (key, text) in value where !["sampleRate", "bitsPerSample", "bitRate"].contains(key) { normalized[key.lowercased()] = text }
        return normalized
    }
}
