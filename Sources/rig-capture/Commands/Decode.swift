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

    @Option(name: .long, help: "Decode every frame in a previously captured .jsonl file.")
    var file: String?

    func run() throws {
        let registry = DecoderRegistry.default
        if listDecoders {
            for decoder in registry.decoders {
                let transports = decoder.transports.map { $0.rawValue }.sorted()
                    .joined(separator: ",")
                print("\(decoder.name)\t[\(transports)]\t\(decoder.summary)")
            }
            return
        }

        if let file {
            try decodeFile(file, registry: registry)
            return
        }

        guard !hex.isEmpty else {
            throw ValidationError("provide hex bytes, --file <capture.jsonl>, or --list-decoders")
        }
        let bytes = try Self.parseHex(hex.joined())
        let matches = registry.decode(bytes)
        guard !matches.isEmpty else {
            print("no decoder matched \(bytes.count) bytes")
            return
        }
        printMatches(matches)
    }

    private func decodeFile(_ path: String, registry: DecoderRegistry) throws {
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        let decoder = JSONDecoder()
        var line = 0
        for raw in contents.split(separator: "\n") {
            line += 1
            guard let data = String(raw).data(using: .utf8),
                let record = try? decoder.decode(CaptureRecord.self, from: data)
            else {
                continue
            }
            let bytes = (try? Self.parseHex(record.hex)) ?? []
            let transport: DecoderTransport = bytes.first == 0xF0 ? .midi : .hid
            let matches = registry.decode(bytes, transport: transport)
            guard !matches.isEmpty else { continue }
            let arrow = record.direction == .toDevice ? "->" : "<-"
            print("line \(line): \(arrow) \(record.endpoint)")
            printMatches(matches, indent: "  ")
        }
    }

    private func printMatches(_ matches: [DecodeMatch], indent: String = "") {
        for match in matches {
            print("\(indent)[\(match.decoder)]")
            for (key, value) in match.fields.sorted(by: { $0.key < $1.key }) {
                print("\(indent)  \(key) = \(value)")
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
