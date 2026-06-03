import Foundation

/// Eventide Opus USB-HID reports (0483:A334, 64-byte vendor pipe, usage page
/// 0xFF00). No framing is known yet, so this is a raw passthrough that simply
/// surfaces length and the leading bytes for inspection. See
/// mcp-midi-controller/docs/research/opus.md.
public struct OpusDecoder: RigDecoder {
    public init() {}

    public let name = "opus"
    public let summary = "Eventide Opus HID (no known framing): raw passthrough"

    public func matches(_ bytes: [UInt8]) -> Bool {
        // HID reports are not SysEx-framed; treat any non-SysEx buffer as a
        // candidate for raw inspection.
        !bytes.isEmpty && !SysEx.isSysEx(bytes)
    }

    public func decode(_ bytes: [UInt8]) -> [String: String] {
        [
            "len": String(bytes.count),
            "head": SysEx.hex(bytes.prefix(8)),
        ]
    }
}
