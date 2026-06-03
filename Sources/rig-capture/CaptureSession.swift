import Foundation
import RigDecoders

/// A live capture session. It is the single sink every backend (the MIDISpy
/// tap, the CoreMIDI source listeners, the HID hook log tail) writes into, so
/// all transports are merged into one ordered frame stream.
///
/// CoreMIDI delivers on background threads, so every mutation is serialized
/// behind a lock.
final class CaptureSession {
    private let writer: CaptureWriter
    private let registry: DecoderRegistry
    private let reassembler = SysExReassembler()
    private let lock = NSLock()
    /// Echo each frame to stdout so the operator sees live traffic.
    private let echo: Bool
    private(set) var frameCount = 0

    init(
        name: String,
        directory: URL,
        registry: DecoderRegistry = .default,
        echo: Bool = true
    ) throws {
        self.writer = try CaptureWriter(sessionName: name, directory: directory)
        self.registry = registry
        self.echo = echo
    }

    /// Feed a raw MIDI byte stream that may need SysEx reassembly across calls.
    func ingestMIDI(endpoint: String, direction: Direction, bytes: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        reassembler.feed(endpoint: endpoint, direction: direction, bytes: bytes) { frame in
            self.record(
                endpoint: endpoint, direction: direction, transport: .midi, bytes: frame, ts: nil)
        }
    }

    /// Feed an already-complete frame (e.g. one HID report) with an optional
    /// capture timestamp from the source.
    func ingestFrame(
        endpoint: String,
        direction: Direction,
        transport: DecoderTransport,
        bytes: [UInt8],
        ts: Double? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }
        record(endpoint: endpoint, direction: direction, transport: transport, bytes: bytes, ts: ts)
    }

    /// Caller must hold `lock`.
    private func record(
        endpoint: String,
        direction: Direction,
        transport: DecoderTransport,
        bytes: [UInt8],
        ts: Double?
    ) {
        guard !bytes.isEmpty else { return }
        let decoded = decodedFields(bytes, transport: transport)
        let rec = CaptureRecord(
            ts: ts ?? Date().timeIntervalSince1970,
            direction: direction,
            endpoint: endpoint,
            bytes: bytes,
            decoded: decoded)
        writer.write(rec)
        frameCount += 1
        if echo {
            print(rec.humanLine)
        }
    }

    private func decodedFields(_ bytes: [UInt8], transport: DecoderTransport) -> [String: String]? {
        let matches = registry.decode(bytes, transport: transport)
        guard !matches.isEmpty else { return nil }
        var out: [String: String] = ["decoder": matches.map { $0.decoder }.joined(separator: ",")]
        for match in matches {
            for (key, value) in match.fields {
                out["\(match.decoder).\(key)"] = value
            }
        }
        return out
    }

    /// Flush any buffered partial SysEx and close the artifacts. Safe to call
    /// once; subsequent backend callbacks are no-ops against a closed handle.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        reassembler.flush { endpoint, direction, frame in
            self.record(
                endpoint: endpoint, direction: direction, transport: .midi, bytes: frame, ts: nil)
        }
        writer.close()
    }
}
