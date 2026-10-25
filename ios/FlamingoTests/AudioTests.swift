import AVFoundation
import XCTest
@testable import Flamingo

final class AudioTests: XCTestCase {
    func testNativeFFmpegDecodeAndMetadata() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "tone.wav")
        let output = folder.appending(path: "tone.caf")
        let rate: UInt32 = 44_100, frames: UInt32 = 4_410, size = frames * 2
        var wav = Data()
        func text(_ value: String) { wav.append(Data(value.utf8)) }
        func u32(_ value: UInt32) { var little = value.littleEndian; withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var little = value.littleEndian; withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) } }
        text("RIFF"); u32(size + 36); text("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(rate); u32(rate * 2); u16(2); u16(16); text("data"); u32(size)
        for sample in 0..<frames { u16(UInt16(bitPattern: Int16(sin(Double(sample) / Double(rate) * 440 * .pi * 2) * 10_000))) }
        try wav.write(to: input)
        let tags = try NativeDecoder.decode(input, output: output)
        XCTAssertEqual(tags["codec"], "pcm_s16le")
        XCTAssertEqual(tags["sampleRate"], "44100")
        let asset = AVURLAsset(url: output)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration).seconds
        XCTAssertTrue(playable)
        XCTAssertEqual(duration, 0.1, accuracy: 0.005)
        XCTAssertGreaterThan(try Data(contentsOf: output).count, Int(size))
    }
    func testBrokenFileFailsWithoutLeavingOutput() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "broken.ape"), output = folder.appending(path: "broken.caf")
        try Data("invalid audio".utf8).write(to: input)
        XCTAssertThrowsError(try NativeDecoder.decode(input, output: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
}
