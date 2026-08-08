import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = UnattendedModeController()
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()

        // Always start inactive. A `true` left behind by a crash must not
        // survive into a new launch, or the hooks would notify unprompted.
        // This write also materialises the key in the plist, so `defaults read`
        // from a hook script succeeds before any session has ever run.
        Preferences.enabled = false

        statusBar = StatusBarController(controller: controller)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The single cleanup path: terminates caffeinate, stops monitoring and
        // clears `enabled`.
        controller.stop()
    }
}
