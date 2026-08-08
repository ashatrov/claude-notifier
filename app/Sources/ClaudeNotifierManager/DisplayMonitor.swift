import CoreGraphics
import Foundation

/// Polls display power state and reports *changes* only.
///
/// Deliberately knows nothing about `caffeinate`: display state must never start
/// or stop an unattended session. Waking the screen silences notifications, it
/// does not end the session.
final class DisplayMonitor {
    private static let interval: TimeInterval = 2.0

    private var timer: Timer?
    private var lastState: Bool?
    private let onChange: (Bool) -> Void

    /// - Parameter onChange: receives `true` when all displays are asleep.
    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        stop()

        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // .common keeps polling alive while a menu is being tracked, which
        // otherwise blocks the default run loop mode.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastState = nil
    }

    private func poll() {
        let asleep = Self.allDisplaysAsleep()
        guard asleep != lastState else { return }
        lastState = asleep
        onChange(asleep)
    }

    /// `CGGetOnlineDisplayList` is the right list here — it includes sleeping
    /// displays. The *active* list excludes them, so it would report "no
    /// displays" the instant the screen slept and hide the transition entirely.
    ///
    /// No displays at all (clamshell, everything unplugged) counts as asleep:
    /// nothing to look at means nobody looking.
    static func allDisplaysAsleep() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return true
        }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return true
        }

        return ids.prefix(Int(count)).allSatisfy { CGDisplayIsAsleep($0) != 0 }
    }
}
