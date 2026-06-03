#include "CSpy.h"

/*
 * Scaffold implementation.
 *
 * The real implementation links against the Snoize MIDISpy client
 * (third_party/MIDISpy/Framework/SpyingMIDIDriver client API), calls
 * MIDISpyClientCreate / MIDISpyPortCreate / MIDISpyPortConnectDestination,
 * and re-emits each MIDIPacketList through RigSpyPacketCallback. Wiring that
 * up requires the vendored sources, so the functions below are stubs that
 * fail cleanly until third_party/MIDISpy is populated (see Makefile target
 * `vendor-midispy`).
 */

static RigSpyPacketCallback g_callback = 0;
static void *g_context = 0;

int RigSpyDriverInstalled(void) {
    /* TODO: stat ~/Library/Audio/MIDI Drivers/MIDI Monitor.driver (MIDISpy). */
    return 0;
}

RigSpyStatus RigSpyStart(RigSpyPacketCallback callback, void *context) {
    if (!RigSpyDriverInstalled()) {
        return RIG_SPY_ERR_DRIVER_MISSING;
    }
    g_callback = callback;
    g_context = context;
    /* TODO: MIDISpyClientCreate + connect to every destination endpoint. */
    return RIG_SPY_ERR_INTERNAL;
}

void RigSpyStop(void) {
    g_callback = 0;
    g_context = 0;
    /* TODO: MIDISpyClientDispose. */
}
