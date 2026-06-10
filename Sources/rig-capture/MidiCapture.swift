import Foundation

#if canImport(CoreMIDI)
    import CoreMIDI
    import CSpy

    /// CoreMIDI capture backend. It merges two directions into one session:
    ///
    ///   * **device -> app** by opening every CoreMIDI *source* endpoint with an
    ///     input port (CoreMIDI fans input out to all clients, so this is
    ///     non-intrusive);
    ///   * **app -> device** by starting the MIDISpy tap (via `CSpy`), which
    ///     delivers a copy of everything sent to any *destination* endpoint.
    ///
    /// Both paths hand raw bytes to `CaptureSession`, which reassembles SysEx and
    /// runs the decoders. CoreMIDI read procs run on their own thread; the session
    /// serializes writes.
    final class MidiCapture {
        private let session: CaptureSession
        private var client = MIDIClientRef()
        private var inputPort = MIDIPortRef()
        private var connectedSources: [MIDIEndpointRef] = []
        private var sourceNames: [MIDIEndpointRef: String] = [:]
        private var spyActive = false

        init(session: CaptureSession) {
            self.session = session
        }

        /// Whether the app -> device (MIDISpy) tap is running. False means
        /// source-only capture (device -> app), e.g. when the driver is missing.
        var spyEnabled: Bool { spyActive }

        /// Number of source endpoints currently connected.
        var sourceCount: Int { connectedSources.count }

        enum CaptureError: Error, CustomStringConvertible {
            case clientCreate(OSStatus)
            case portCreate(OSStatus)

            var description: String {
                switch self {
                case .clientCreate(let s): return "MIDIClientCreate failed (OSStatus \(s))"
                case .portCreate(let s): return "MIDIInputPortCreate failed (OSStatus \(s))"
                }
            }
        }

        /// Set up the client + input port, connect every source, and (optionally)
        /// start the MIDISpy tap. Returns once capture is live.
        func start(enableSpy: Bool) throws {
            var status = MIDIClientCreate("rig-capture" as CFString, nil, nil, &client)
            guard status == noErr else { throw CaptureError.clientCreate(status) }

            let refcon = Unmanaged.passUnretained(self).toOpaque()
            status = MIDIInputPortCreate(
                client, "rig-capture-in" as CFString, Self.readProc, refcon, &inputPort)
            guard status == noErr else { throw CaptureError.portCreate(status) }

            let sources = MIDIGetNumberOfSources()
            for i in 0..<sources {
                let src = MIDIGetSource(i)
                sourceNames[src] = MIDISupport.endpointName(src)
                // Carry the endpoint ref through as the connection refCon so the
                // read proc knows which source a packet came from.
                let token = UnsafeMutableRawPointer(bitPattern: UInt(src))
                if MIDIPortConnectSource(inputPort, src, token) == noErr {
                    connectedSources.append(src)
                }
            }

            if enableSpy {
                startSpy(context: refcon)
            }
        }

        private func startSpy(context: UnsafeMutableRawPointer) {
            // RigSpyStart returns RIG_SPY_OK (0) on success, RIG_SPY_ERR_DRIVER_MISSING
            // (1) when the MIDISpy driver is not installed, or another RIG_SPY_ERR_*.
            let status = RigSpyStart(Self.spyCallback, context)
            switch status {
            case 0:
                spyActive = true
            case 1:
                warn(
                    "MIDISpy driver not installed; app->device tap disabled. "
                        + "Run `make vendor-midispy && make install-driver`, then re-login.")
            default:
                warn("MIDISpy tap failed to start (status \(status)); capturing device->app only.")
            }
        }

        private func warn(_ message: String) {
            FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
        }

        func stop() {
            if spyActive {
                RigSpyStop()
                spyActive = false
            }
            for src in connectedSources {
                MIDIPortDisconnectSource(inputPort, src)
            }
            connectedSources.removeAll()
            if inputPort != 0 { MIDIPortDispose(inputPort) }
            if client != 0 { MIDIClientDispose(client) }
        }

        // MARK: device -> app (source listener)

        private func handleSource(
            _ endpoint: MIDIEndpointRef,
            _ packetList: UnsafePointer<MIDIPacketList>
        ) {
            let name = sourceNames[endpoint] ?? MIDISupport.endpointName(endpoint)
            for packet in packetList.unsafeSequence() {
                let length = Int(packet.pointee.length)
                guard length > 0 else { continue }
                let bytes = withUnsafeBytes(of: packet.pointee.data) { raw in
                    Array(raw.prefix(length))
                }
                session.ingestMIDI(endpoint: name, direction: .toApp, bytes: bytes)
            }
        }

        // Legacy packet-based read proc: it delivers the raw MIDI 1.0 byte stream
        // (including SysEx split across packets) directly, which is exactly what the
        // reassembler wants -- simpler and more faithful here than the UMP-based
        // MIDIReceiveBlock for SysEx-heavy editor protocols.
        private static let readProc: MIDIReadProc = { packetList, readProcRefCon, srcConnRefCon in
            guard let readProcRefCon else { return }
            let me = Unmanaged<MidiCapture>.fromOpaque(readProcRefCon).takeUnretainedValue()
            let endpoint = MIDIEndpointRef(truncatingIfNeeded: Int(bitPattern: srcConnRefCon))
            me.handleSource(endpoint, packetList)
        }

        // MARK: app -> device (MIDISpy tap)

        private func handleSpy(_ endpoint: MIDIEndpointRef, _ bytes: [UInt8]) {
            let name = MIDISupport.endpointName(endpoint)
            session.ingestMIDI(endpoint: name, direction: .toDevice, bytes: bytes)
        }

        private static let spyCallback: RigSpyPacketCallback = { endpointRef, data, len, context in
            guard let context, let data, len > 0 else { return }
            let me = Unmanaged<MidiCapture>.fromOpaque(context).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: data, count: len))
            me.handleSpy(endpointRef, bytes)
        }
    }
#endif
