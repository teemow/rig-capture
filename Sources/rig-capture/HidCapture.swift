import Foundation

/// USB-HID capture backend. It injects the `CHidHook` dylib into a vendor
/// editor app (preferring Frida, falling back to `DYLD_INSERT_LIBRARIES`), then
/// tails the hook's report log and folds each report into the capture session.
///
/// The dylib writes raw report lines to `RIG_HIDHOOK_LOG`; that file is the
/// untouched artifact, while the session's `.jsonl`/`.log` carry the decoded
/// (Opus passthrough) view. Both live under the gitignored `captures/` dir.
final class HidCapture {
    enum Injector: String {
        case frida
        case dyld
    }

    enum HidError: Error, CustomStringConvertible {
        case dylibMissing(String)
        case appMissing(String)
        case launchFailed(String)

        var description: String {
            switch self {
            case .dylibMissing(let p):
                return "CHidHook dylib not found at \(p) "
                    + "(build it with `make hidhook`, or pass --dylib)"
            case .appMissing(let p):
                return "app binary not found: \(p)"
            case .launchFailed(let m):
                return "failed to launch injector: \(m)"
            }
        }
    }

    private let session: CaptureSession
    private let appPath: String
    private let dylibPath: String
    private let logPath: String
    private let injector: Injector
    private let endpointLabel: String

    private var process: Process?
    private var tailThread: Thread?
    private var stopping = false
    private let tailDone = DispatchSemaphore(value: 0)

    init(
        session: CaptureSession,
        appPath: String,
        dylibPath: String,
        logURL: URL,
        injector: Injector
    ) {
        self.session = session
        self.appPath = appPath
        self.dylibPath = dylibPath
        self.logPath = logURL.path
        self.injector = injector
        self.endpointLabel = Self.appLabel(appPath)
    }

    func run() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dylibPath) else { throw HidError.dylibMissing(dylibPath) }
        let binary = Self.resolveBinary(appPath)
        guard fm.fileExists(atPath: binary) else { throw HidError.appMissing(binary) }

        // Fresh, empty log so the tail only sees this session's reports.
        fm.createFile(atPath: logPath, contents: nil)

        let process = try makeProcess(binary: binary)
        self.process = process
        let waiter = InterruptWaiter { [weak self] in self?.terminate() }
        // App quit on its own -> unblock the waiter too.
        process.terminationHandler = { _ in waiter.trigger() }

        let tail = Thread { [weak self] in self?.tailLoop() }
        tail.stackSize = 1 << 20
        self.tailThread = tail
        tail.start()

        do {
            try process.run()
        } catch {
            stopping = true
            tailDone.wait()
            throw HidError.launchFailed(
                "\(error.localizedDescription) (is `\(injector.rawValue)` installed?)")
        }

        print("rig-capture: HID capture of \(endpointLabel) via \(injector.rawValue).")
        print("  Press Ctrl-C to stop.")
        waiter.wait()

        terminate()
        // Let the dylib flush its final reports, then stop and join the tail so
        // no report is written after the session is closed by the caller.
        Thread.sleep(forTimeInterval: 0.2)
        stopping = true
        tailDone.wait()
    }

    private func terminate() {
        if let process, process.isRunning {
            process.terminate()
        }
    }

    private func makeProcess(binary: String) throws -> Process {
        let process = Process()
        var env = ProcessInfo.processInfo.environment
        env["RIG_HIDHOOK_LOG"] = logPath
        env["RIG_HIDHOOK_DYLIB"] = dylibPath

        switch injector {
        case .frida:
            let script = try writeInjectScript()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["frida", "-f", binary, "-l", script]
        case .dyld:
            // Fallback for unsigned/dev builds; notarized apps need SIP relaxed.
            env["DYLD_INSERT_LIBRARIES"] = dylibPath
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = []
        }
        process.environment = env
        return process
    }

    /// Generate a tiny Frida script that dlopen()s the hook dylib into the
    /// target. Written to a temp file so we don't depend on the working dir.
    private func writeInjectScript() throws -> String {
        let js = """
        const dylib = Process.env.RIG_HIDHOOK_DYLIB || \(jsString(dylibPath));
        try {
          Module.load(dylib);
          console.log("[rig-capture] loaded HID hook: " + dylib);
        } catch (e) {
          console.error("[rig-capture] failed to load " + dylib + ": " + e.message);
        }
        """
        let pid = ProcessInfo.processInfo.processIdentifier
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rig-capture-inject-\(pid).js")
        try js.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    // MARK: log tailing

    private func tailLoop() {
        defer { tailDone.signal() }
        guard let fh = FileHandle(forReadingAtPath: logPath) else { return }
        defer { try? fh.close() }
        var buffer = Data()
        while true {
            let chunk = fh.availableData
            if chunk.isEmpty {
                if stopping { break }
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let line = String(data: lineData, encoding: .utf8) {
                    ingest(line: line)
                }
            }
        }
    }

    /// Parse one hook line: `<ts> <OUT|IN> type=<n> id=<n> len=<n>: hh hh ...`
    private func ingest(line: String) {
        guard let colon = line.firstIndex(of: ":") else { return }
        let meta = line[..<colon].split(separator: " ")
        guard meta.count >= 2 else { return }
        let ts = Double(meta[0])
        let direction: Direction = (meta[1] == "OUT") ? .toDevice : .toApp
        let hexPart = line[line.index(after: colon)...]
        let bytes = hexPart.split(separator: " ").compactMap { UInt8($0, radix: 16) }
        guard !bytes.isEmpty else { return }
        session.ingestFrame(
            endpoint: endpointLabel, direction: direction, transport: .hid, bytes: bytes, ts: ts)
    }

    // MARK: path helpers

    /// Resolve the executable inside a `.app` bundle, or pass through a binary.
    static func resolveBinary(_ path: String) -> String {
        if path.hasSuffix(".app"), let bundle = Bundle(path: path),
            let exe = bundle.executablePath {
            return exe
        }
        return path
    }

    static func appLabel(_ path: String) -> String {
        let last = (path as NSString).lastPathComponent
        if last.hasSuffix(".app") {
            return String(last.dropLast(4))
        }
        return last
    }

    /// Default dylib path: sibling of the running rig-capture executable.
    static func defaultDylibPath() -> String {
        let exe = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "rig-capture")
        let dir = exe.resolvingSymlinksInPath().deletingLastPathComponent()
        return dir.appendingPathComponent("libCHidHook.dylib").path
    }

    private func jsString(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
