# MIDISpy (vendored)

This directory holds the [Snoize MIDISpy](https://github.com/krevis/MIDIApps)
CoreMIDI driver and client API used by the `CSpy` target to passively observe
the **app -> device** MIDI direction (the same mechanism MIDI Monitor uses).

It is **not committed** here yet. Populate it with:

```sh
make vendor-midispy
```

which clones the BSD-licensed `MIDISpy` sources into `_src/` and copies the
client shim sources (`MIDISpyClient.{h,m}` and helpers) into the `CSpy` target.
MIDISpy keeps its own license; see the `LICENSE` it ships with.

## How CSpy picks it up

`Sources/CSpy/CSpy.c` guards the real implementation with
`#if __has_include("MIDISpyClient.h")`. With the header copied into
`Sources/CSpy/include/`, CSpy compiles the real tap; without it, CSpy builds as
a clean stub that reports the driver as missing (so `swift build`/CI stays green
with no vendored, non-committed third-party code).

The shim uses this subset of the MIDISpy client API:

- `MIDISpyInstallDriverIfNecessary()`
- `MIDISpyClientCreate()` / `MIDISpyClientDispose()`
- `MIDISpyPortCreate()` / `MIDISpyPortDispose()`
- `MIDISpyPortConnectDestination()`
- the `kMIDISpyDriverMissing` status

If the upstream layout/API differs, adjust `CSpy.c` and the `vendor-midispy`
copy globs in the `Makefile` accordingly.

Installing the driver itself (into `~/Library/Audio/MIDI Drivers/`) is a
one-time host setup step (`make install-driver`); `MIDISpyInstallDriverIfNecessary`
also drops a bundled copy on first run.
