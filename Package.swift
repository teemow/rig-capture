// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "rig-capture",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // The capture daemon / CLI.
        .executable(name: "rig-capture", targets: ["rig-capture"]),
        // The injectable HID-hook dylib, loaded into a vendor editor app via
        // Frida or DYLD_INSERT_LIBRARIES. Built as a standalone .dylib.
        .library(name: "CHidHook", type: .dynamic, targets: ["CHidHook"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        // C shim wrapping the Snoize MIDISpy client API (vendored in
        // third_party/MIDISpy). Lets the daemon receive a copy of everything
        // an app sends to a CoreMIDI destination.
        .target(
            name: "CSpy"
        ),
        // Injectable dylib that interposes IOHIDDevice report calls so we can
        // log raw USB-HID report buffers from a vendor app.
        .target(
            name: "CHidHook"
        ),
        // Known-framing decoders (H90/TRPC, ML10X, Roland/Boss, Opus HID).
        // Kept as a top-level directory per the design.
        .target(
            name: "RigDecoders",
            path: "decoders"
        ),
        .executableTarget(
            name: "rig-capture",
            dependencies: [
                "CSpy",
                "RigDecoders",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "RigDecodersTests",
            dependencies: ["RigDecoders"]
        ),
    ]
)
