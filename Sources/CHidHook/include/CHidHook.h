#ifndef CHIDHOOK_H
#define CHIDHOOK_H

/*
 * CHidHook is an injectable dylib. It interposes the IOHIDDevice report calls
 * so we can log every raw HID report buffer (length + direction) exchanged
 * between a vendor editor app and a USB-HID device -- primarily the Eventide
 * Opus (0483:A334, 64-byte vendor pipe, usage page 0xFF00).
 *
 * Injection:
 *   - Preferred: Frida   -> frida -f "/Applications/Torpedo Remote.app/..." \
 *                            -l inject.js   (which dlopen()s this dylib)
 *   - Fallback (unsigned/dev builds):
 *       DYLD_INSERT_LIBRARIES=/path/to/libCHidHook.dylib /path/to/app
 *
 * The interposed symbols are defined in CHidHook.c via the Mach-O
 * __DATA,__interpose section; there is no public API to call -- loading the
 * dylib is enough. This header only documents the contract.
 *
 * Hooked IOHIDDevice entry points:
 *   - IOHIDDeviceSetReport / IOHIDDeviceSetReportWithCallback   (host -> device)
 *   - IOHIDDeviceGetReport / IOHIDDeviceGetReportWithCallback   (device -> host)
 *   - IOHIDDeviceRegisterInputReportCallback                    (device -> host,
 *                                                                async stream)
 *
 * Output: each report is written as a line to the file named by the
 * RIG_HIDHOOK_LOG environment variable (default: stderr). Line format:
 *   <unix_ts> <OUT|IN> type=<n> id=<n> len=<n>: <hh hh ...>
 * which `rig-capture capture hid` tails and folds into the capture session.
 */

#endif /* CHIDHOOK_H */
