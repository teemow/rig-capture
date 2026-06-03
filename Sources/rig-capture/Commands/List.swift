import ArgumentParser
import Foundation

#if canImport(CoreMIDI)
import CoreMIDI
#endif

/// `rig-capture list` -- enumerate CoreMIDI devices, sources and destinations
/// so a capture target can be chosen.
struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List CoreMIDI devices/endpoints available to capture."
    )

    @Flag(name: .long, help: "Also list (offline) devices and their entities.")
    var devices: Bool = false

    func run() throws {
        #if canImport(CoreMIDI)
        if devices {
            Self.printDevices()
            print("")
        }
        Self.printEndpoints(
            heading: "CoreMIDI destinations (app -> device, tapped via MIDISpy):",
            count: MIDIGetNumberOfDestinations(),
            at: MIDIGetDestination)
        Self.printEndpoints(
            heading: "CoreMIDI sources (device -> app, opened directly):",
            count: MIDIGetNumberOfSources(),
            at: MIDIGetSource)
        #else
        print("CoreMIDI is only available on macOS; rig-capture is a macOS tool.")
        throw ExitCode.failure
        #endif
    }

    #if canImport(CoreMIDI)
    private static func printEndpoints(
        heading: String,
        count: Int,
        at: (Int) -> MIDIEndpointRef
    ) {
        print(heading)
        if count == 0 {
            print("  (none)")
            return
        }
        for i in 0..<count {
            let ep = at(i)
            let name = MIDISupport.endpointName(ep)
            let offline = MIDISupport.isOffline(ep) ? " [offline]" : ""
            print("  [\(i)] \(name)\(offline)")
        }
    }

    private static func printDevices() {
        let count = MIDIGetNumberOfDevices()
        print("CoreMIDI devices:")
        if count == 0 {
            print("  (none)")
            return
        }
        for i in 0..<count {
            let device = MIDIGetDevice(i)
            let name = MIDISupport.stringProperty(device, kMIDIPropertyName) ?? "<device>"
            var details: [String] = []
            if let mfr = MIDISupport.stringProperty(device, kMIDIPropertyManufacturer) {
                details.append("mfr=\(mfr)")
            }
            if let model = MIDISupport.stringProperty(device, kMIDIPropertyModel) {
                details.append("model=\(model)")
            }
            if MIDISupport.isOffline(device) {
                details.append("offline")
            }
            let suffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"
            print("  [\(i)] \(name)\(suffix)")
            let entities = MIDIDeviceGetNumberOfEntities(device)
            for e in 0..<entities {
                let entity = MIDIDeviceGetEntity(device, e)
                let entityName = MIDISupport.stringProperty(entity, kMIDIPropertyName) ?? "<entity>"
                let srcs = MIDIEntityGetNumberOfSources(entity)
                let dsts = MIDIEntityGetNumberOfDestinations(entity)
                print("        - \(entityName): \(srcs) source(s), \(dsts) destination(s)")
            }
        }
    }
    #endif
}
