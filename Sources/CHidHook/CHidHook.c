#include "CHidHook.h"

#if defined(__APPLE__)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <IOKit/hid/IOHIDDevice.h>

/*
 * DYLD interpose plumbing. Each entry in the __DATA,__interpose section
 * replaces a call to `original` with a call to `replacement` for the image
 * this dylib is injected into.
 */
#define RIG_INTERPOSE(replacement, original)                                   \
    __attribute__((used)) static struct {                                      \
        const void *replacement;                                               \
        const void *original;                                                  \
    } _interpose_##original                                                    \
        __attribute__((section("__DATA,__interpose"))) = {                     \
            (const void *)&replacement, (const void *)&original}

static FILE *rig_log(void) {
    static FILE *fp = NULL;
    if (fp == NULL) {
        const char *path = getenv("RIG_HIDHOOK_LOG");
        fp = (path && *path) ? fopen(path, "a") : stderr;
        if (fp == NULL) {
            fp = stderr;
        }
    }
    return fp;
}

static void rig_dump(const char *dir, IOHIDReportType type, uint32_t reportID,
                     const uint8_t *report, CFIndex length) {
    FILE *fp = rig_log();
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    double t = (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
    fprintf(fp, "%.6f %s type=%d id=%u len=%ld:", t, dir, (int)type, reportID,
            (long)length);
    for (CFIndex i = 0; i < length; i++) {
        fprintf(fp, " %02x", report[i]);
    }
    fputc('\n', fp);
    fflush(fp);
}

/* --- IOHIDDeviceSetReport (host -> device, synchronous) --- */
IOReturn rig_IOHIDDeviceSetReport(IOHIDDeviceRef device, IOHIDReportType reportType,
                                  CFIndex reportID, const uint8_t *report,
                                  CFIndex reportLength) {
    rig_dump("OUT", reportType, (uint32_t)reportID, report, reportLength);
    return IOHIDDeviceSetReport(device, reportType, reportID, report, reportLength);
}
RIG_INTERPOSE(rig_IOHIDDeviceSetReport, IOHIDDeviceSetReport);

/* --- IOHIDDeviceGetReport (device -> host, synchronous) --- */
IOReturn rig_IOHIDDeviceGetReport(IOHIDDeviceRef device, IOHIDReportType reportType,
                                  CFIndex reportID, uint8_t *report,
                                  CFIndex *pReportLength) {
    IOReturn r = IOHIDDeviceGetReport(device, reportType, reportID, report,
                                      pReportLength);
    if (r == kIOReturnSuccess && pReportLength) {
        rig_dump("IN", reportType, (uint32_t)reportID, report, *pReportLength);
    }
    return r;
}
RIG_INTERPOSE(rig_IOHIDDeviceGetReport, IOHIDDeviceGetReport);

/*
 * Wrapping callback-based APIs: the app passes its own callback + context. We
 * register our own thunk that logs the report, then forwards to the app's
 * original callback so behaviour is unchanged. The small context box leaks on
 * re-registration, which is acceptable for a short-lived capture session.
 */
typedef struct {
    IOHIDReportCallback callback;
    void *context;
} RigReportBox;

static RigReportBox *rig_box(IOHIDReportCallback cb, void *ctx) {
    RigReportBox *box = (RigReportBox *)malloc(sizeof(RigReportBox));
    if (box) {
        box->callback = cb;
        box->context = ctx;
    }
    return box;
}

static void rig_report_thunk(void *context, IOReturn result, void *sender,
                             IOHIDReportType type, uint32_t reportID,
                             uint8_t *report, CFIndex reportLength) {
    if (result == kIOReturnSuccess) {
        rig_dump("IN", type, reportID, report, reportLength);
    }
    RigReportBox *box = (RigReportBox *)context;
    if (box && box->callback) {
        box->callback(box->context, result, sender, type, reportID, report,
                      reportLength);
    }
}

/* --- IOHIDDeviceRegisterInputReportCallback (device -> host, async stream) --- */
void rig_IOHIDDeviceRegisterInputReportCallback(IOHIDDeviceRef device,
                                                uint8_t *report,
                                                CFIndex reportLength,
                                                IOHIDReportCallback callback,
                                                void *context) {
    IOHIDDeviceRegisterInputReportCallback(device, report, reportLength,
                                           rig_report_thunk,
                                           rig_box(callback, context));
}
RIG_INTERPOSE(rig_IOHIDDeviceRegisterInputReportCallback,
              IOHIDDeviceRegisterInputReportCallback);

/* --- IOHIDDeviceGetReportWithCallback (device -> host, async one-shot) --- */
IOReturn rig_IOHIDDeviceGetReportWithCallback(IOHIDDeviceRef device,
                                              IOHIDReportType reportType,
                                              CFIndex reportID, uint8_t *report,
                                              CFIndex *pReportLength,
                                              CFTimeInterval timeout,
                                              IOHIDReportCallback callback,
                                              void *context) {
    return IOHIDDeviceGetReportWithCallback(device, reportType, reportID, report,
                                            pReportLength, timeout,
                                            rig_report_thunk,
                                            rig_box(callback, context));
}
RIG_INTERPOSE(rig_IOHIDDeviceGetReportWithCallback,
              IOHIDDeviceGetReportWithCallback);

/* --- IOHIDDeviceSetReportWithCallback (host -> device, async) --- */
IOReturn rig_IOHIDDeviceSetReportWithCallback(IOHIDDeviceRef device,
                                              IOHIDReportType reportType,
                                              CFIndex reportID,
                                              const uint8_t *report,
                                              CFIndex reportLength,
                                              CFTimeInterval timeout,
                                              IOHIDReportCallback callback,
                                              void *context) {
    rig_dump("OUT", reportType, (uint32_t)reportID, report, reportLength);
    return IOHIDDeviceSetReportWithCallback(device, reportType, reportID, report,
                                            reportLength, timeout, callback,
                                            context);
}
RIG_INTERPOSE(rig_IOHIDDeviceSetReportWithCallback,
              IOHIDDeviceSetReportWithCallback);

#endif /* __APPLE__ */
