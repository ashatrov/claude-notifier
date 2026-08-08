import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = UnattendedModeController()
    private var statusBar: StatusBarController?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()

        // Always start inactive. A `true` left behind by a crash must not
        // survive into a new launch, or the hooks would notify unprompted.
        // This write also materialises the key in the plist, so `defaults read`
        // from a hook script succeeds before any session has ever run.
        Preferences.enabled = false

        installTerminationSignalHandlers()
        statusBar = StatusBarController(controller: controller)
    }

    /// Routes catchable "please exit" signals through `NSApp.terminate`, so
    /// `kill` and `pkill` clean up exactly like the Quit menu item.
    ///
    /// Without this the default disposition kills the process outright,
    /// `applicationWillTerminate` never runs, and `enabled` is left switched on —
    /// meaning every later Claude hook notifies your phone until the app is
    /// opened again.
    ///
    /// SIGKILL cannot be caught by any process, so Force Quit is still a hard
    /// stop. Relaunching clears the flag.
    private func installTerminationSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            // The dispatch source only sees the signal if the default action is
            // suppressed first.
            signal(signalNumber, SIG_IGN)

            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The single cleanup path: terminates caffeinate, stops monitoring and
        // clears `enabled`.
        controller.stop()
    }
}
