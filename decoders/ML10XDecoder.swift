import Foundation

/// Hotone/ML10X SysEx framing:
/// `F0 00 21 24 07 00 <op1> <op2> ... <cksum> F7`, with a 7-bit XOR checksum.
///
/// Flags whether the checksum verifies and surfaces the opcode bytes so the
/// controller "Message Type" writes can be told apart from the editor's read
/// opcodes. See mcp-midi-controller/docs/research/ml10x.md.
public struct ML10XDecoder: RigDecoder {
    public init() {}

    public let name = "ml10x"
    public let summary = "Hotone ML10X: F0 00 21 24 07 00 <op...> <cksum> F7"

    private static let prefix: [UInt8] = [0xF0, 0x00, 0x21, 0x24, 0x07, 0x00]

    public func matches(_ bytes: [UInt8]) -> Bool {
        SysEx.isSysEx(bytes) && bytes.count >= 9 && Array(bytes.prefix(6)) == Self.prefix
    }

    public func decode(_ bytes: [UInt8]) -> [String: String] {
        // Body is everything between the prefix and the trailing checksum + F7.
        let bodyStart = Self.prefix.count
        let checksumIndex = bytes.count - 2
        let body = bytes[bodyStart..<checksumIndex]
        let expected = SysEx.xorChecksum(body)
        let actual = bytes[checksumIndex] & 0x7F
        var fields: [String: String] = [
            "op": SysEx.hex(body.prefix(2)),
            "body_len": String(body.count),
            "checksum_ok": String(expected == actual),
        ]
        if body.count >= 1 {
            fields["op1"] = String(format: "%02X", body[body.startIndex])
        }
        if body.count >= 2 {
            fields["op2"] = String(format: "%02X", body[body.startIndex + 1])
        }
        return fields
    }
}
