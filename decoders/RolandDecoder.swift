import Foundation

/// Roland/Boss SysEx (e.g. SL-2): `F0 41 <dev> 00 00 00 00 1D <cmd> ...`,
/// where cmd is RQ1 (0x11, read request) or DT1 (0x12, data set), followed by
/// address + data + a Roland checksum. Used to confirm capture framing.
/// See mcp-midi-controller/docs/research/sl-2.md.
public struct RolandDecoder: RigDecoder {
    public init() {}

    public let name = "roland"
    public let summary = "Roland/Boss SL-2: F0 41 <dev> 00 00 00 00 1D <RQ1|DT1> ... F7"

    private static let manufacturer: UInt8 = 0x41
    private static let modelId: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x1D]

    public func matches(_ bytes: [UInt8]) -> Bool {
        guard SysEx.isSysEx(bytes), bytes.count >= 11 else { return false }
        guard bytes[1] == Self.manufacturer else { return false }
        // bytes[2] is the device id; model id follows at offset 3.
        return Array(bytes[3..<8]) == Self.modelId
    }

    public func decode(_ bytes: [UInt8]) -> [String: String] {
        let command = bytes[8]
        let commandName: String
        switch command {
        case 0x11: commandName = "RQ1"
        case 0x12: commandName = "DT1"
        default: commandName = "unknown"
        }
        // Roland checksum covers address + data (everything between command and
        // the checksum byte that precedes F7).
        let checkable = bytes[9..<(bytes.count - 2)]
        let sum = checkable.reduce(0) { (Int($0) + Int($1)) }
        let expected = UInt8((128 - (sum % 128)) % 128)
        let actual = bytes[bytes.count - 2] & 0x7F
        return [
            "device_id": String(format: "%02X", bytes[2]),
            "command": commandName,
            "address": SysEx.hex(checkable.prefix(4)),
            "checksum_ok": String(expected == actual),
        ]
    }
}
