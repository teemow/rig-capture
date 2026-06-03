import Foundation

/// Blocks the calling thread until SIGINT/SIGTERM (or an explicit `trigger()`),
/// so a long-running capture can shut down cleanly. Uses a semaphore rather
/// than a run loop: CoreMIDI delivers on its own threads and the HID backend
/// tails a file on a worker thread, so no main run loop is required.
final class InterruptWaiter {
    private let semaphore = DispatchSemaphore(value: 0)
    private var sources: [DispatchSourceSignal] = []
    private let onSignal: (() -> Void)?
    private let once = NSLock()
    private var fired = false

    init(onSignal: (() -> Void)? = nil) {
        self.onSignal = onSignal
        install()
    }

    private func install() {
        // Ignore the default disposition so the dispatch sources receive them.
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let queue = DispatchQueue(label: "rig-capture.signals")
        for sig in [SIGINT, SIGTERM] {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
            source.setEventHandler { [weak self] in self?.trigger() }
            source.resume()
            sources.append(source)
        }
    }

    /// Unblock `wait()`. Safe to call multiple times (e.g. SIGINT plus a child
    /// process exiting); `onSignal` runs at most once.
    func trigger() {
        once.lock()
        let first = !fired
        fired = true
        once.unlock()
        if first { onSignal?() }
        semaphore.signal()
    }

    /// Block until the first signal/`trigger()`, then stop handling signals.
    func wait() {
        semaphore.wait()
        sources.forEach { $0.cancel() }
    }
}

enum Signals {
    /// Convenience: install handlers, block until interrupted, then return.
    static func waitForInterrupt(onSignal: (() -> Void)? = nil) {
        InterruptWaiter(onSignal: onSignal).wait()
    }
}
