import ArgumentParser
import Foundation

#if canImport(CoreMIDI)
import CoreMIDI
#endif

/// `rig-capture list` -- enumerate CoreMIDI endpoints (and, later, HID devices)
/// so a capture target can be chosen.
struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List CoreMIDI devices/endpoints available to capture."
    )

    func run() throws {
        #if canImport(CoreMIDI)
        let destinations = MIDIGetNumberOfDestinations()
        let sources = MIDIGetNumberOfSources()
        print("CoreMIDI destinations (app -> device):")
        for i in 0..<destinations {
            let ep = MIDIGetDestination(i)
            print("  [\(i)] \(Self.endpointName(ep))")
        }
        print("CoreMIDI sources (device -> app):")
        for i in 0..<sources {
            let ep = MIDIGetSource(i)
            print("  [\(i)] \(Self.endpointName(ep))")
        }
        #else
        print("CoreMIDI is only available on macOS; rig-capture is a macOS tool.")
        throw ExitCode.failure
        #endif
    }

    #if canImport(CoreMIDI)
    private static func endpointName(_ endpoint: MIDIEndpointRef) -> String {
        var unmanaged: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &unmanaged)
        guard status == noErr, let cf = unmanaged?.takeRetainedValue() else {
            return "<unknown>"
        }
        return cf as String
    }
    #endif
}
