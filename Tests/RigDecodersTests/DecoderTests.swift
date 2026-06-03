import XCTest
@testable import RigDecoders

final class DecoderTests: XCTestCase {
    func testH90Envelope() {
        // F0 1C 77 00 | 01 02 03 04 | 0A 0B 0C 0D | F7
        let bytes: [UInt8] = [0xF0, 0x1C, 0x77, 0x00, 0x01, 0x02, 0x03, 0x04,
                              0x0A, 0x0B, 0x0C, 0x0D, 0xF7]
        let decoder = H90Decoder()
        XCTAssertTrue(decoder.matches(bytes))
        let fields = decoder.decode(bytes)
        // 14-bit id from 0x01,0x02 -> (1 << 7) | 2 = 130.
        XCTAssertEqual(fields["message_id_14bit"], "130")
        XCTAssertEqual(fields["payload_len"], "4")
    }

    func testML10XChecksum() {
        let prefix: [UInt8] = [0xF0, 0x00, 0x21, 0x24, 0x07, 0x00]
        let body: [UInt8] = [0x12, 0x34, 0x56]
        let cksum = body.reduce(UInt8(0)) { $0 ^ $1 } & 0x7F
        let bytes = prefix + body + [cksum, 0xF7]
        let decoder = ML10XDecoder()
        XCTAssertTrue(decoder.matches(bytes))
        XCTAssertEqual(decoder.decode(bytes)["checksum_ok"], "true")
    }

    func testRolandDT1() {
        // F0 41 10 00 00 00 00 1D 12 <addr+data> <cksum> F7
        let head: [UInt8] = [0xF0, 0x41, 0x10, 0x00, 0x00, 0x00, 0x00, 0x1D, 0x12]
        let payload: [UInt8] = [0x00, 0x00, 0x00, 0x01, 0x05]
        let sum = payload.reduce(0) { Int($0) + Int($1) }
        let cksum = UInt8((128 - (sum % 128)) % 128)
        let bytes = head + payload + [cksum, 0xF7]
        let decoder = RolandDecoder()
        XCTAssertTrue(decoder.matches(bytes))
        let fields = decoder.decode(bytes)
        XCTAssertEqual(fields["command"], "DT1")
        XCTAssertEqual(fields["checksum_ok"], "true")
    }

    func testRegistryDispatch() {
        let h90: [UInt8] = [0xF0, 0x1C, 0x77, 0x00, 0x01, 0x02, 0x03, 0x04, 0x0A, 0xF7]
        let matches = DecoderRegistry.default.decode(h90)
        XCTAssertTrue(matches.contains { $0.decoder == "h90" })
    }
}
