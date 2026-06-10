import Foundation

#if canImport(CoreMIDI)
    import CoreMIDI

    /// Shared CoreMIDI helpers used by `list` and the capture listeners.
    enum MIDISupport {
        /// Read a CFString property off any CoreMIDI object, or nil.
        static func stringProperty(_ object: MIDIObjectRef, _ key: CFString) -> String? {
            var unmanaged: Unmanaged<CFString>?
            guard MIDIObjectGetStringProperty(object, key, &unmanaged) == noErr,
                let cf = unmanaged?.takeRetainedValue()
            else {
                return nil
            }
            return cf as String
        }

        /// Read an Int property off any CoreMIDI object, or nil.
        static func intProperty(_ object: MIDIObjectRef, _ key: CFString) -> Int32? {
            var value: Int32 = 0
            guard MIDIObjectGetIntegerProperty(object, key, &value) == noErr else {
                return nil
            }
            return value
        }

        /// Best-effort human-readable endpoint name. Prefers the display name
        /// (which CoreMIDI already builds as "Device Port"); falls back to the
        /// endpoint's own name, then a placeholder.
        static func endpointName(_ endpoint: MIDIEndpointRef) -> String {
            if let display = stringProperty(endpoint, kMIDIPropertyDisplayName), !display.isEmpty {
                return display
            }
            if let name = stringProperty(endpoint, kMIDIPropertyName), !name.isEmpty {
                return name
            }
            return "<endpoint \(endpoint)>"
        }

        /// True when the endpoint is currently offline (disconnected device).
        static func isOffline(_ endpoint: MIDIEndpointRef) -> Bool {
            (intProperty(endpoint, kMIDIPropertyOffline) ?? 0) != 0
        }
    }
#endif
