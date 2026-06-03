import ArgumentParser

@main
struct RigCapture: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rig-capture",
        abstract: "Capture traffic between vendor editor apps and rig devices.",
        discussion: """
            rig-capture is a read-only research tool. It observes CoreMIDI and \
            USB-HID traffic so undecoded protocols can be reverse-engineered. \
            It never writes to or drives a device.

            Raw captures contain rig-specific names/IDs and stay out of git \
            (see .gitignore). Only generic protocol findings should be \
            hand-copied into mcp-midi-controller/docs/research/<device>.md.
            """,
        version: "0.1.0",
        subcommands: [List.self, Capture.self, Decode.self]
    )
}
