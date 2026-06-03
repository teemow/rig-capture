import Foundation

/// Direction of an observed message relative to the rig device.
enum Direction: String, Codable {
    /// App -> device (e.g. CoreMIDI send, IOHIDDeviceSetReport).
    case toDevice = "to_device"
    /// Device -> app (e.g. CoreMIDI source reply, IOHIDDeviceGetReport).
    case toApp = "to_app"
}

/// One observed message. Serialized as a single JSONL line.
struct CaptureRecord: Codable {
    /// Seconds since the Unix epoch, with sub-millisecond resolution.
    let ts: Double
    let direction: Direction
    /// Endpoint name / app identifier the message was observed on.
    let endpoint: String
    /// Raw bytes, lower-case hex without separators.
    let hex: String
    /// Optional decoded fields produced by a known-framing decoder.
    let decoded: [String: String]?

    init(ts: Double = Date().timeIntervalSince1970,
         direction: Direction,
         endpoint: String,
         bytes: [UInt8],
         decoded: [String: String]? = nil) {
        self.ts = ts
        self.direction = direction
        self.endpoint = endpoint
        self.hex = bytes.map { String(format: "%02x", $0) }.joined()
        self.decoded = decoded
    }
}

/// Writes capture sessions to a gitignored `captures/` directory as a pair of
/// artifacts: a machine-readable `.jsonl` and a human-readable hexdump `.log`.
final class CaptureWriter {
    private let jsonl: FileHandle
    private let log: FileHandle
    private let encoder = JSONEncoder()

    init(sessionName: String, directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = directory.appendingPathComponent(sessionName)
        let jsonlURL = base.appendingPathExtension("jsonl")
        let logURL = base.appendingPathExtension("log")
        fm.createFile(atPath: jsonlURL.path, contents: nil)
        fm.createFile(atPath: logURL.path, contents: nil)
        self.jsonl = try FileHandle(forWritingTo: jsonlURL)
        self.log = try FileHandle(forWritingTo: logURL)
    }

    func write(_ record: CaptureRecord) {
        if let data = try? encoder.encode(record) {
            jsonl.write(data)
            jsonl.write(Data("\n".utf8))
        }
        let arrow = record.direction == .toDevice ? "->" : "<-"
        var line = String(format: "%.6f %@ %@ %@",
                          record.ts, arrow, record.endpoint, record.hex)
        if let decoded = record.decoded, !decoded.isEmpty {
            let fields = decoded.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            line += "  [\(fields)]"
        }
        line += "\n"
        log.write(Data(line.utf8))
    }

    func close() {
        try? jsonl.close()
        try? log.close()
    }
}
