# rig-capture

A standalone macOS tool that captures the traffic between vendor **editor apps**
and rig **devices**, so undecoded protocols can be reverse-engineered. It is the
Mac counterpart to the Linux probes (`cmd/usb-probe`, `cmd/widi-probe`) in
[`mcp-midi-controller`](https://github.com/teemow/mcp-midi-controller).

It captures two transports:

- **CoreMIDI** -- passive [MIDISpy](third_party/MIDISpy/README.md)-style tap, so
  closed vendor apps need no reconfiguration (they auto-bind to the real
  endpoint and would ignore a virtual proxy port).
- **USB-HID** -- API interposition: a logging dylib (`CHidHook`) hooks the
  `IOHIDDevice` report calls, injected via Frida.

> **Read-only.** rig-capture only observes. It never writes to or drives a
> device, matching the read-only research methodology of the main project.

## Architecture

```
  Vendor editor app                              Rig device
  (H90 Control / BOSS TS /                        (H90, ML10X,
   Chrome WebMIDI / Torpedo Remote)                Opus, SL-2, ...)
        |   CoreMIDI send         ---------------->   |
        |   CoreMIDI reply        <----------------   |
        |   IOHIDDevice set/get report  ---------->   |
        |                                             |
   [MIDISpy tap]  app->device  -----\
   [source listen] device->app -----+--->  rig-capture daemon  --->  captures/*.jsonl + *.log
   [CHidHook dylib] HID reports -----/                                (gitignored)
```

## Repo layout

| Path                     | Purpose |
|--------------------------|---------|
| `Package.swift`          | SwiftPM package: `rig-capture` executable + `CSpy`/`CHidHook` C targets. |
| `Sources/rig-capture/`   | CLI/daemon (`list`, `capture midi`, `capture hid`, `decode`). |
| `Sources/CSpy/`          | C shim around the MIDISpy client API (app -> device tap). |
| `Sources/CHidHook/`      | Injectable dylib hooking `IOHIDDevice` report calls. Built as a standalone `.dylib`. |
| `decoders/`              | Known-framing decoders (H90/TRPC, ML10X, Roland/Boss, Opus HID). |
| `third_party/MIDISpy/`   | Vendored Snoize MIDISpy driver + client (BSD); see its README. |
| `captures/`              | Session output (**gitignored**). |

## Prerequisites

- macOS 13+ and a Swift toolchain (`swift --version`).
- [Frida](https://frida.re/) for HID injection (`brew install frida`).
- The MIDISpy driver installed under `~/Library/Audio/MIDI Drivers/`
  (`make vendor-midispy && make install-driver`).
- **HID only:** notarized apps require SIP relaxed once for injection
  (`csrutil enable --without debug`, or a full disable, from Recovery). This is
  a documented prerequisite, not something the tool automates.

## Build

```sh
swift build              # or: make build
swift test               # decoder unit tests
make hidhook             # build just libCHidHook.dylib
```

## Usage

```sh
# Enumerate CoreMIDI endpoints (add --devices for devices + entities).
swift run rig-capture list

# Passively tap CoreMIDI (app<->device) into captures/<name>.{jsonl,log}.
# Ctrl-C stops the session cleanly. --no-spy captures device->app only.
swift run rig-capture capture midi --name h90-preset-load

# Capture USB-HID reports by injecting CHidHook into a vendor app (Frida).
swift run rig-capture capture hid --app "/Applications/Torpedo Remote.app" --name opus-dump
# Unsigned/dev builds can use the DYLD fallback instead of Frida:
swift run rig-capture capture hid --app ./MyTool --dyld

# Decode hex bytes, a whole capture file, or list the decoders.
swift run rig-capture decode "F0 1C 77 00 01 02 03 04 0A F7"
swift run rig-capture decode --file captures/h90-preset-load.jsonl
swift run rig-capture decode --list-decoders
```

Each session writes two artifacts to `captures/` (gitignored):

- `*.jsonl` -- machine-readable: `{ts, direction, endpoint, hex, decoded}` per line.
- `*.log` -- human-readable hexdump with reassembled SysEx.

## Decoders

The `decode` subcommand recognizes the framing of devices that are not yet
fully decoded and surfaces envelope/header fields to speed up the work:

- **H90 / TRPC** -- `F0 1C 77 00 <hdr4> <flatbuffers> F7`; surfaces the 14-bit
  message id and FlatBuffers root offset.
- **ML10X** -- `F0 00 21 24 07 00 <op...> <cksum> F7`; verifies the 7-bit XOR
  checksum and flags controller writes vs editor reads.
- **Roland/Boss (SL-2)** -- model id `00 00 00 00 1D`, RQ1/DT1 + checksum.
- **Opus HID** -- raw passthrough (no known framing yet).

## Public vs. private

This repo is **public**. Raw captures contain rig-specific names/IDs and live
state, so they **never** go in git (`captures/`, `private/`, `*.local.*` are all
gitignored). Only **generic protocol findings** -- opcode meanings, framing,
bitmask layout -- get hand-copied into the main project's
`docs/research/<device>.md`. This mirrors the public/private rule of
`mcp-midi-controller`.

## License

MIT (see [LICENSE](LICENSE)). The vendored MIDISpy sources keep their own
BSD-style license.
