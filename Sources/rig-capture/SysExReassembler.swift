import Foundation

/// Reassembles a raw MIDI 1.0 byte stream (as delivered by CoreMIDI packets)
/// into complete messages, joining SysEx (`F0 … F7`) that arrives across
/// several packets. State is kept per stream key so multiple endpoints and
/// both directions can be interleaved.
///
/// Not thread-safe on its own; `CaptureSession` serializes access.
final class SysExReassembler {
    private struct Stream {
        let endpoint: String
        let direction: Direction
        var sysex: [UInt8] = []
        var inSysEx = false
        var pending: [UInt8] = []
        var expected = 0
        var runningStatus: UInt8 = 0
    }

    private var streams: [String: Stream] = [:]

    private static func key(_ endpoint: String, _ direction: Direction) -> String {
        "\(direction.rawValue)|\(endpoint)"
    }

    /// Standard MIDI 1.0 message length for a status byte (including the status
    /// byte itself). Returns 1 for SysEx start/realtime/unknown.
    private static func messageLength(_ status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0x80, 0x90, 0xA0, 0xB0, 0xE0:
            return 3
        case 0xC0, 0xD0:
            return 2
        default:
            break
        }
        switch status {
        case 0xF2:  // Song Position Pointer
            return 3
        case 0xF1, 0xF3:  // MTC Quarter Frame, Song Select
            return 2
        default:
            return 1
        }
    }

    /// Feed a chunk of raw MIDI bytes for one endpoint/direction. `emit` is
    /// called once per reassembled message with its complete bytes.
    func feed(endpoint: String, direction: Direction, bytes: [UInt8], emit: ([UInt8]) -> Void) {
        let k = Self.key(endpoint, direction)
        var s = streams[k] ?? Stream(endpoint: endpoint, direction: direction)

        for b in bytes {
            if s.inSysEx {
                if b == 0xF7 {
                    s.sysex.append(b)
                    emit(s.sysex)
                    s.sysex = []
                    s.inSysEx = false
                } else if b >= 0xF8 {
                    // System real-time may be interleaved inside SysEx; surface
                    // it as its own message without disturbing the SysEx buffer.
                    emit([b])
                } else if b >= 0x80 {
                    // Any other status aborts the running SysEx.
                    emit(s.sysex)
                    s.sysex = []
                    s.inSysEx = false
                    Self.startMessage(&s, status: b, emit: emit)
                } else {
                    s.sysex.append(b)
                }
                continue
            }

            if b == 0xF0 {
                s.inSysEx = true
                s.sysex = [b]
                s.pending = []
                s.runningStatus = 0
            } else if b >= 0xF8 {
                emit([b])
            } else if b >= 0x80 {
                Self.startMessage(&s, status: b, emit: emit)
            } else {
                // Data byte: continue the pending message, or apply running status.
                if !s.pending.isEmpty {
                    s.pending.append(b)
                    if s.pending.count >= s.expected {
                        emit(s.pending)
                        s.pending = []
                    }
                } else if s.runningStatus != 0 {
                    s.pending = [s.runningStatus, b]
                    s.expected = Self.messageLength(s.runningStatus)
                    if s.pending.count >= s.expected {
                        emit(s.pending)
                        s.pending = []
                    }
                }
                // else: stray data byte with no status -> ignore.
            }
        }
        streams[k] = s
    }

    private static func startMessage(_ s: inout Stream, status: UInt8, emit: ([UInt8]) -> Void) {
        let length = messageLength(status)
        // System common (0xF1..0xF7) clears running status; channel voice sets it.
        s.runningStatus = status < 0xF0 ? status : 0
        if length == 1 {
            emit([status])
            s.pending = []
            s.expected = 0
        } else {
            s.pending = [status]
            s.expected = length
        }
    }

    /// Emit any buffered-but-incomplete SysEx (e.g. at session shutdown) so a
    /// truncated transfer is not silently dropped. Reassembler state is reset.
    func flush(emit: (String, Direction, [UInt8]) -> Void) {
        for (_, s) in streams where s.inSysEx && !s.sysex.isEmpty {
            emit(s.endpoint, s.direction, s.sysex)
        }
        streams.removeAll()
    }
}
