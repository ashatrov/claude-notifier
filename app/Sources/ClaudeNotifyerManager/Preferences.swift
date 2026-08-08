import Foundation

/// Thin wrapper over `UserDefaults.standard`.
///
/// The bundle identifier stays `com.ashatrov.claude-notifyer` even though the
/// app is named "Claude Notifyer Manager" — it is the preferences domain the
/// notifier hook scripts read, so renaming it would silently break them.
///
/// These therefore land in `~/Library/Preferences/com.ashatrov.claude-notifyer.plist`
/// where plain `defaults read` finds them. That only holds while the app runs as
/// a real, unsandboxed bundle — see README.
enum Preferences {
    enum Key {
        static let enabled = "enabled"
        static let turnDisplayOffAfterStart = "turnDisplayOffAfterStart"
        static let forceNotifications = "forceNotifications"
        static let lastCustomDuration = "lastCustomDuration"
    }

    private static let defaults = UserDefaults.standard

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.turnDisplayOffAfterStart: true,
            Key.forceNotifications: false,
            Key.lastCustomDuration: 4.0,
        ])
    }

    /// The flag the notifier hooks gate on:
    ///
    ///     defaults read com.ashatrov.claude-notifyer enabled
    ///
    /// True only while every display is asleep during an unattended session.
    static var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    static var turnDisplayOffAfterStart: Bool {
        get { defaults.bool(forKey: Key.turnDisplayOffAfterStart) }
        set { defaults.set(newValue, forKey: Key.turnDisplayOffAfterStart) }
    }

    /// Ignore the screen rule and notify for the whole session. Still requires a
    /// session — this never notifies on its own.
    ///
    /// Set through `UnattendedModeController.setForceNotifications(_:)` so the
    /// change applies right away rather than at the next screen transition.
    static var forceNotifications: Bool {
        get { defaults.bool(forKey: Key.forceNotifications) }
        set { defaults.set(newValue, forKey: Key.forceNotifications) }
    }

    /// Hours, remembered between uses of the Custom… dialog.
    static var lastCustomDuration: Double {
        get { defaults.double(forKey: Key.lastCustomDuration) }
        set { defaults.set(newValue, forKey: Key.lastCustomDuration) }
    }
}
