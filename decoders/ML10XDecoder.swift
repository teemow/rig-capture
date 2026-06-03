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
    public let summary = "Morningstar ML10X: F0 00 21 24 07 00 <op...> <cksum> F7"
    public let transports: Set<DecoderTransport> = [.midi]

    private static let prefix: [UInt8] = [0xF0, 0x00, 0x21, 0x24, 0x07, 0x00]

    public func matches(_ bytes: [UInt8]) -> Bool {
        SysEx.isSysEx(bytes) && bytes.count >= 9 && Array(bytes.prefix(6)) == Self.prefix
    }

    public func decode(_ bytes: [UInt8]) -> [String: String] {
        // Body is everything between the prefix and the trailing checksum + F7.
        let bodyStart = Self.prefix.count
        let checksumIndex = bytes.count - 2
        let body = bytes[bodyStart..<checksumIndex]
        // Checksum is XOR of every byte from F0 up to (not incl.) the checksum,
        // masked to 7 bits (see docs/research/ml10x.md).
        let expected = SysEx.xorChecksum(bytes[0..<checksumIndex])
        let actual = bytes[checksumIndex] & 0x7F
        var fields: [String: String] = [
            "op": SysEx.hex(body.prefix(2)),
            "body_len": String(body.count),
            "checksum_ok": String(expected == actual),
        ]
        if body.count >= 1 {
            let op1 = body[body.startIndex]
            fields["op1"] = String(format: "%02X", op1)
            // op1 message class per docs/research/ml10x.md.
            switch op1 {
            case 0x00: fields["class"] = "request"
            case 0x01: fields["class"] = "status"
            case 0x06: fields["class"] = "data_block"
            default: break
            }
        }
        if body.count >= 2 {
            fields["op2"] = String(format: "%02X", body[body.startIndex + 1])
        }
        return fields
    }
}
