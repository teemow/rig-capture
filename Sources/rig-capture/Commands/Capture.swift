import ArgumentParser
import Foundation

/// `rig-capture capture <midi|hid>` -- record a session to `captures/`.
struct Capture: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Capture a MIDI or HID session.",
        subcommands: [Midi.self, Hid.self]
    )

    struct Options: ParsableArguments {
        @Option(name: .shortAndLong, help: "Session name; output is captures/<name>.{jsonl,log}.")
        var name: String = "session-\(Int(Date().timeIntervalSince1970))"

        @Option(help: "Output directory (gitignored).")
        var out: String = "captures"

        func makeWriter() throws -> CaptureWriter {
            try CaptureWriter(sessionName: name, directory: URL(fileURLWithPath: out))
        }
    }

    /// `rig-capture capture midi` -- passive CoreMIDI tap.
    ///
    /// app -> device is observed via the MIDISpy CoreMIDI driver (CSpy);
    /// device -> app is observed by opening each device source endpoint. Both
    /// reassemble running SysEx (F0 ... F7) across packets before recording.
    struct Midi: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Passively tap CoreMIDI (app<->device) into a capture session."
        )

        @OptionGroup var options: Options

        func run() throws {
            let writer = try options.makeWriter()
            defer { writer.close() }
            // TODO: RigSpyStart (CSpy) for app -> device + open device sources
            // for device -> app; reassemble SysEx; writer.write(record).
            throw CleanExit.message(
                "MIDI capture wiring (CSpy/MIDISpy + source listeners) is not implemented yet."
            )
        }
    }

    /// `rig-capture capture hid` -- API interposition via the CHidHook dylib.
    struct Hid: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Capture USB-HID reports by injecting CHidHook into an app."
        )

        @OptionGroup var options: Options

        @Argument(help: "Path to the vendor app bundle/binary to launch and hook.")
        var app: String

        func run() throws {
            // TODO: spawn `frida -f <app> -l inject.js` (loading libCHidHook.dylib)
            // or set DYLD_INSERT_LIBRARIES; tail RIG_HIDHOOK_LOG into the writer.
            throw CleanExit.message(
                "HID capture wiring (Frida/DYLD injection of CHidHook) is not implemented yet."
            )
        }
    }
}
