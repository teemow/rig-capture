import Foundation

/// A known-framing decoder for one device family. Decoders are read-only: they
/// recognize a byte stream and surface envelope/header fields to help pin down
/// undecoded opcodes. They do not attempt to fully parse payloads.
public protocol RigDecoder {
    /// Short identifier, e.g. "h90".
    var name: String { get }
    /// One-line description of what this decoder recognizes.
    var summary: String { get }
    /// Does this byte stream look like this decoder's framing?
    func matches(_ bytes: [UInt8]) -> Bool
    /// Extract envelope/header fields. Only called when `matches` is true.
    func decode(_ bytes: [UInt8]) -> [String: String]
}

/// Result of a successful decode.
public struct DecodeMatch {
    public let decoder: String
    public let fields: [String: String]
}

/// Helpers shared by the SysEx decoders.
enum SysEx {
    static let start: UInt8 = 0xF0
    static let end: UInt8 = 0xF7

    static func isSysEx(_ bytes: [UInt8]) -> Bool {
        bytes.first == start && bytes.last == end
    }

    /// 7-bit XOR checksum over a slice (used by ML10X-style framing).
    static func xorChecksum(_ slice: ArraySlice<UInt8>) -> UInt8 {
        slice.reduce(UInt8(0)) { ($0 ^ $1) } & 0x7F
    }

    static func hex(_ bytes: ArraySlice<UInt8>) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
