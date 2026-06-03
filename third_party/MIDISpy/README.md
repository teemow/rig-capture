# MIDISpy (vendored)

This directory holds the [Snoize MIDISpy](https://github.com/krevis/MIDIApps)
CoreMIDI driver and client API used by the `CSpy` target to passively observe
the **app -> device** MIDI direction (the same mechanism MIDI Monitor uses).

It is **not committed** here yet. Populate it with:

```sh
make vendor-midispy
```

which fetches the BSD-licensed `MIDISpy` sources into this directory. MIDISpy
keeps its own license; see the `LICENSE` it ships with. The `CSpy` shim links
against `MIDISpyClientCreate` / `MIDISpyPortConnectDestination` from these
sources.

Installing the driver itself (into `~/Library/Audio/MIDI Drivers/`) is a
one-time host setup step, also wired into the `Makefile` (`make install-driver`).
