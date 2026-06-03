// Frida loader for the CHidHook dylib.
//
// Usage:
//   frida -f "/Applications/Torpedo Remote.app/Contents/MacOS/Torpedo Remote" \
//         -l scripts/inject.js
//
// Set RIG_HIDHOOK_DYLIB to the built dylib path (see `make hidhook`) and
// RIG_HIDHOOK_LOG to where reports should be written.
const dylib =
  Process.env.RIG_HIDHOOK_DYLIB ||
  ".build/debug/libCHidHook.dylib";

try {
  Module.load(dylib);
  console.log("[rig-capture] loaded HID hook: " + dylib);
} catch (e) {
  console.error("[rig-capture] failed to load " + dylib + ": " + e.message);
}
