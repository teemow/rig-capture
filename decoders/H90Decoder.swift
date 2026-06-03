import Foundation

/// Eventide H90 "TRPC" SysEx envelope: `F0 1C 77 00 <hdr4> <flatbuffers> F7`.
///
/// Surfaces the 4-byte header (which carries a 14-bit message id / status byte)
/// and the start of the FlatBuffers payload, to help pin the still-undecoded
/// `Dot9MessageType` opcodes. See mcp-midi-controller/docs/research/h90.md.
public struct H90Decoder: RigDecoder {
    public init() {}

    public let name = "h90"
    public let summary = "Eventide H90 TRPC: F0 1C 77 00 <hdr4> <flatbuffers> F7"

    private static let prefix: [UInt8] = [0xF0, 0x1C, 0x77, 0x00]

    public func matches(_ bytes: [UInt8]) -> Bool {
        SysEx.isSysEx(bytes) && bytes.count >= 9 && Array(bytes.prefix(4)) == Self.prefix
    }

    public func decode(_ bytes: [UInt8]) -> [String: String] {
        let header = bytes[4..<8]
        // Reconstruct a 14-bit id from the first two header bytes (7 bits each).
        let messageId = (UInt16(header[header.startIndex] & 0x7F) << 7)
            | UInt16(header[header.startIndex + 1] & 0x7F)
        let payload = bytes[8..<(bytes.count - 1)]
        var fields: [String: String] = [
            "header": SysEx.hex(header),
            "message_id_14bit": String(messageId),
            "payload_len": String(payload.count),
        ]
        if payload.count >= 4 {
            fields["flatbuffers_root_offset"] = SysEx.hex(payload.prefix(4))
        }
        return fields
    }
}
