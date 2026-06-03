import ArgumentParser
import Foundation

/// `rig-capture capture <midi|hid>` -- record a session to `captures/`.
struct Capture: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Capture a MIDI or HID session.",
        subcommands: [Midi.self, Hid.self]
    )

    /// Options shared by both capture backends.
    struct Options: ParsableArguments {
        @Option(name: .shortAndLong, help: "Session name; output is captures/<name>.{jsonl,log}.")
        var name: String = Options.defaultName()

        @Option(help: "Output directory (gitignored).")
        var out: String = "captures"

        @Flag(name: .long, help: "Do not echo captured frames to stdout.")
        var quiet: Bool = false

        var directoryURL: URL { URL(fileURLWithPath: out) }

        func makeSession() throws -> CaptureSession {
            try CaptureSession(name: name, directory: directoryURL, echo: !quiet)
        }

        static func defaultName() -> String {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd-HHmmss"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            return "session-\(fmt.string(from: Date()))"
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

        @Flag(name: .long, help: "Capture device->app only (skip the MIDISpy app->device tap).")
        var noSpy: Bool = false

        func run() throws {
            #if canImport(CoreMIDI)
            let session = try options.makeSession()
            let capture = MidiCapture(session: session)
            do {
                try capture.start(enableSpy: !noSpy)
            } catch {
                session.close()
                throw error
            }

            let spyState = capture.spyEnabled ? "on" : "off"
            let base = options.directoryURL.appendingPathComponent(options.name).path
            print("rig-capture: capturing -> \(base).{jsonl,log}")
            print("  sources connected: \(capture.sourceCount), app->device tap: \(spyState)")
            print("  Press Ctrl-C to stop.")

            Signals.waitForInterrupt()

            capture.stop()
            session.close()
            print("\nrig-capture: stopped. \(session.frameCount) frame(s) written.")
            #else
            throw CleanExit.message(
                "CoreMIDI is only available on macOS; rig-capture is a macOS tool.")
            #endif
        }
    }

    /// `rig-capture capture hid` -- API interposition via the CHidHook dylib.
    struct Hid: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Capture USB-HID reports by injecting CHidHook into an app."
        )

        @OptionGroup var options: Options

        @Option(name: .long, help: "Path to the vendor app bundle (.app) or binary to hook.")
        var app: String

        @Option(name: .long, help: "Path to libCHidHook.dylib (default: next to rig-capture).")
        var dylib: String?

        @Flag(name: .long, help: "Use DYLD_INSERT_LIBRARIES instead of Frida (dev builds only).")
        var dyld: Bool = false

        func run() throws {
            let session = try options.makeSession()
            let dylibPath = dylib ?? HidCapture.defaultDylibPath()
            let logURL = options.directoryURL
                .appendingPathComponent(options.name)
                .appendingPathExtension("hidlog")
            let capture = HidCapture(
                session: session,
                appPath: app,
                dylibPath: dylibPath,
                logURL: logURL,
                injector: dyld ? .dyld : .frida)
            defer {
                session.close()
                print("\nrig-capture: stopped. \(session.frameCount) report(s) written.")
            }
            try capture.run()
        }
    }
}
