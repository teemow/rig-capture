import ArgumentParser
import Foundation
import RigDecoders

/// `rig-capture decode` -- run the known-framing decoders over hex input
/// (raw bytes on the command line or a previously captured `.jsonl`).
struct Decode: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Decode hex bytes with the known-framing decoders."
    )

    @Argument(help: "Hex bytes, e.g. \"F0 1C 77 00 ... F7\" (spaces optional).")
    var hex: [String] = []

    @Flag(name: .long, help: "List the available decoders and exit.")
    var listDecoders: Bool = false

    func run() throws {
        let registry = DecoderRegistry.default
        if listDecoders {
            for decoder in registry.decoders {
                print("\(decoder.name)\t\(decoder.summary)")
            }
            return
        }
        let bytes = try Self.parseHex(hex.joined())
        let matches = registry.decode(bytes)
        guard !matches.isEmpty else {
            print("no decoder matched \(bytes.count) bytes")
            return
        }
        for match in matches {
            print("[\(match.decoder)]")
            for (key, value) in match.fields.sorted(by: { $0.key < $1.key }) {
                print("  \(key) = \(value)")
            }
        }
    }

    static func parseHex(_ input: String) throws -> [UInt8] {
        let cleaned = input.filter { !$0.isWhitespace }
        guard cleaned.count % 2 == 0 else {
            throw ValidationError("hex input must have an even number of digits")
        }
        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                throw ValidationError("invalid hex byte: \(cleaned[index..<next])")
            }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
