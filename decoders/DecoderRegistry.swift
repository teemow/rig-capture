import Foundation

/// Collects the known-framing decoders and runs them over a byte stream.
public struct DecoderRegistry {
    public let decoders: [RigDecoder]

    public init(decoders: [RigDecoder]) {
        self.decoders = decoders
    }

    /// The decoders shipped with rig-capture.
    public static let `default` = DecoderRegistry(decoders: [
        H90Decoder(),
        ML10XDecoder(),
        RolandDecoder(),
        OpusDecoder(),
    ])

    /// Run every matching decoder and return their fields. When `transport` is
    /// given, only decoders that apply to that transport are considered.
    public func decode(_ bytes: [UInt8], transport: DecoderTransport? = nil) -> [DecodeMatch] {
        decoders.compactMap { decoder in
            if let transport, !decoder.transports.contains(transport) { return nil }
            guard decoder.matches(bytes) else { return nil }
            return DecodeMatch(decoder: decoder.name, fields: decoder.decode(bytes))
        }
    }
}
