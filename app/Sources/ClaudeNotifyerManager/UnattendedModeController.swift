import AppKit
import Foundation

/// Owns one unattended session: the `caffeinate` process, the display monitor,
/// and the `enabled` preference derived from it.
final class UnattendedModeController {
    struct Session {
        let start: Date
        let end: Date
        let duration: TimeInterval
    }

    private(set) var session: Session?

    /// Fires when the session starts or ends, so the status item can redraw.
    var onStateChange: (() -> Void)?

    private var caffeinate: Process?
    private var displayMonitor: DisplayMonitor?
    private var activity: NSObjectProtocol?
    private var isStoppingManually = false

    /// Last state the monitor reported. Remembered because the monitor only
    /// reports *changes*, so toggling Force mid-session has nothing to read
    /// otherwise.
    private var displaysAsleep = false

    /// Last value written to the preference, so repeated identical writes are
    /// skipped.
    private var appliedEnabled: Bool?

    var isActive: Bool { session != nil }

    var remaining: TimeInterval {
        guard let session else { return 0 }
        return max(0, session.end.timeIntervalSinceNow)
    }

    // MARK: - Notification flag

    /// The one rule: notify while a session is running and either the screen is
    /// off or the user forced it on.
    private func applyNotificationState() {
        let desired = isActive && (Preferences.forceNotifications || displaysAsleep)
        guard desired != appliedEnabled else { return }
        appliedEnabled = desired
        Preferences.enabled = desired
    }

    /// Takes effect immediately, mid-session included.
    func setForceNotifications(_ force: Bool) {
        Preferences.forceNotifications = force
        applyNotificationState()
    }

    // MARK: - Start

    func start(hours: Double) {
        // Never two sessions at once.
        stop()

        let duration = (hours * 3600).rounded()
        guard duration >= 1 else { return }

        isStoppingManually = false
        // Assume the screen is on until the monitor's first poll says otherwise.
        displaysAsleep = false
        appliedEnabled = false
        Preferences.enabled = false

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -i prevents idle *system* sleep only. The display stays free to sleep,
        // which is exactly what gates the notifications.
        process.arguments = ["-i", "-t", String(Int(duration))]
        process.terminationHandler = { [weak self] _ in
            // Termination handlers run on an arbitrary queue.
            DispatchQueue.main.async { self?.caffeinateDidExit() }
        }

        do {
            try process.run()
        } catch {
            NSLog("claude-notifyer-manager: could not launch caffeinate: \(error)")
            return
        }

        caffeinate = process

        let now = Date()
        session = Session(start: now, end: now.addingTimeInterval(duration), duration: duration)

        // Stops App Nap from coalescing the 2s poll timer. Deliberately *not*
        // .userInitiated: that implies .idleSystemSleepDisabled, which would keep
        // the Mac awake after Stop. caffeinate alone owns sleep prevention.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Claude Notifyer Manager unattended session"
        )
        // So macOS cannot kill us without running applicationWillTerminate,
        // which is what guarantees `enabled` is never left set.
        ProcessInfo.processInfo.disableSuddenTermination()

        let monitor = DisplayMonitor { [weak self] asleep in
            guard let self else { return }
            self.displaysAsleep = asleep
            self.applyNotificationState()
        }
        monitor.start()
        displayMonitor = monitor

        onStateChange?()

        if Preferences.turnDisplayOffAfterStart {
            // Let the menu finish closing first — dismissing it counts as user
            // activity and can wake the display straight back up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard self?.isActive == true else { return }
                Self.sleepDisplayNow()
            }
        }
    }

    // MARK: - Stop

    /// Idempotent — safe to call with no session running.
    func stop() {
        displayMonitor?.stop()
        displayMonitor = nil

        if let process = caffeinate {
            caffeinate = nil
            if process.isRunning {
                // Tells caffeinateDidExit this was us, not a timeout.
                isStoppingManually = true
                // Only ever this one process. Terminal sessions and other apps
                // may be running their own caffeinate, so `killall` is never OK.
                process.terminate()
            }
        }

        let wasActive = session != nil
        session = nil

        // Unconditional, not routed through applyNotificationState: ending a
        // session must clear the flag even if Force is left switched on.
        displaysAsleep = false
        appliedEnabled = false
        Preferences.enabled = false

        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
            ProcessInfo.processInfo.enableSuddenTermination()
        }

        if wasActive {
            onStateChange?()
        }
    }

    private func caffeinateDidExit() {
        if isStoppingManually {
            isStoppingManually = false
            return
        }
        // The -t timeout expired on its own; unwind exactly as Stop would.
        stop()
    }

    // MARK: - Display

    static func sleepDisplayNow() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        do {
            try process.run()
        } catch {
            NSLog("claude-notifyer-manager: could not run pmset displaysleepnow: \(error)")
        }
    }
}
