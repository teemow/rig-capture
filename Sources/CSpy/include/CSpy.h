#ifndef CSPY_H
#define CSPY_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Thin C wrapper around the Snoize MIDISpy client API (vendored in
 * third_party/MIDISpy). MIDISpy installs a CoreMIDI driver that forwards a
 * copy of every MIDI packet sent to any destination endpoint to connected spy
 * clients -- the same mechanism MIDI Monitor uses. This lets rig-capture
 * observe the app -> device direction passively, without reconfiguring the
 * (closed-source) vendor editor apps.
 *
 * Replies in the device -> app direction are captured separately by opening
 * the device source endpoints directly from Swift (CoreMIDI fans input out to
 * all clients), so they are not handled here.
 */

/* Callback invoked for each MIDI packet observed flowing to a destination.
 *   endpointRef : the CoreMIDI MIDIEndpointRef (UInt32) of the destination.
 *   data/len    : raw MIDI bytes (SysEx may arrive across multiple calls).
 *   context     : opaque pointer passed to RigSpyStart.
 */
typedef void (*RigSpyPacketCallback)(uint32_t endpointRef,
                                      const uint8_t *data,
                                      size_t len,
                                      void *context);

/* Return codes (functions return these as plain int to stay unambiguous when
 * imported into Swift). */
enum {
    RIG_SPY_OK = 0,
    RIG_SPY_ERR_DRIVER_MISSING = 1, /* MIDISpy driver not installed */
    RIG_SPY_ERR_CONNECT = 2,        /* could not connect spy client */
    RIG_SPY_ERR_INTERNAL = 3,
};

/* Is the MIDISpy driver installed in ~/Library/Audio/MIDI Drivers/ ? */
int RigSpyDriverInstalled(void);

/* Connect a spy client and begin delivering packets to the callback.
 * Returns RIG_SPY_OK (0) on success, or one of the RIG_SPY_ERR_* codes. */
int RigSpyStart(RigSpyPacketCallback callback, void *context);

/* Tear down the spy client. */
void RigSpyStop(void);

#ifdef __cplusplus
}
#endif

#endif /* CSPY_H */
