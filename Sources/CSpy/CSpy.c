#include "CSpy.h"

/*
 * C shim around the Snoize MIDISpy client API.
 *
 * MIDISpy installs a CoreMIDI driver that forwards a copy of every packet sent
 * to any destination endpoint to connected spy clients -- the mechanism MIDI
 * Monitor uses. That lets rig-capture observe the app -> device direction
 * passively, without reconfiguring the (closed) vendor editor apps.
 *
 * The MIDISpy client sources are vendored on demand (see `make vendor-midispy`,
 * which copies `MIDISpyClient.{h,m}` + helpers into this target). When the
 * header is present we compile the real client; otherwise this builds as a
 * clean stub that reports the driver as missing, so `swift build` is green in
 * CI without the vendored (BSD-licensed) sources.
 */

#if defined(__APPLE__)

#include <CoreMIDI/CoreMIDI.h>
#include <stdint.h>

#if __has_include("MIDISpyClient.h")
#include "MIDISpyClient.h"
#define RIG_HAVE_MIDISPY 1
#endif

static RigSpyPacketCallback g_callback = 0;
static void *g_context = 0;

#if defined(RIG_HAVE_MIDISPY)

static MIDISpyClientRef g_client = NULL;
static MIDISpyPortRef g_port = NULL;

/* CoreMIDI read proc: MIDISpy delivers tapped packets here. The connection
 * refCon carries the destination endpoint ref we passed at connect time. */
static void RigSpyReadProc(const MIDIPacketList *pktlist, void *readProcRefCon,
                           void *srcConnRefCon) {
    (void)readProcRefCon;
    if (!g_callback || !pktlist) {
        return;
    }
    uint32_t endpoint = (uint32_t)(uintptr_t)srcConnRefCon;
    const MIDIPacket *packet = &pktlist->packet[0];
    for (UInt32 i = 0; i < pktlist->numPackets; i++) {
        if (packet->length > 0) {
            g_callback(endpoint, packet->data, (size_t)packet->length, g_context);
        }
        packet = MIDIPacketNext(packet);
    }
}

int RigSpyDriverInstalled(void) {
    /* Installs the bundled driver if absent; returns noErr when present. */
    return MIDISpyInstallDriverIfNecessary() == noErr;
}

int RigSpyStart(RigSpyPacketCallback callback, void *context) {
    g_callback = callback;
    g_context = context;

    OSStatus err = MIDISpyClientCreate(&g_client);
    if (err == kMIDISpyDriverMissing) {
        return RIG_SPY_ERR_DRIVER_MISSING;
    }
    if (err != noErr || g_client == NULL) {
        return RIG_SPY_ERR_INTERNAL;
    }

    err = MIDISpyPortCreate(g_client, RigSpyReadProc, NULL, &g_port);
    if (err != noErr || g_port == NULL) {
        MIDISpyClientDispose(g_client);
        g_client = NULL;
        return RIG_SPY_ERR_CONNECT;
    }

    /* Tap every destination endpoint; carry the endpoint ref as the refCon. */
    ItemCount count = MIDIGetNumberOfDestinations();
    for (ItemCount i = 0; i < count; i++) {
        MIDIEndpointRef dest = MIDIGetDestination(i);
        if (dest != 0) {
            MIDISpyPortConnectDestination(g_port, dest, (void *)(uintptr_t)dest);
        }
    }
    return RIG_SPY_OK;
}

void RigSpyStop(void) {
    if (g_port) {
        MIDISpyPortDispose(g_port);
        g_port = NULL;
    }
    if (g_client) {
        MIDISpyClientDispose(g_client);
        g_client = NULL;
    }
    g_callback = 0;
    g_context = 0;
}

#else /* !RIG_HAVE_MIDISPY -- vendored sources not present */

int RigSpyDriverInstalled(void) { return 0; }

int RigSpyStart(RigSpyPacketCallback callback, void *context) {
    g_callback = callback;
    g_context = context;
    return RIG_SPY_ERR_DRIVER_MISSING;
}

void RigSpyStop(void) {
    g_callback = 0;
    g_context = 0;
}

#endif /* RIG_HAVE_MIDISPY */

#else /* !__APPLE__ -- rig-capture is a macOS tool; keep non-Apple builds clean */

int RigSpyDriverInstalled(void) { return 0; }

int RigSpyStart(RigSpyPacketCallback callback, void *context) {
    (void)callback;
    (void)context;
    return RIG_SPY_ERR_DRIVER_MISSING;
}

void RigSpyStop(void) {}

#endif /* __APPLE__ */
