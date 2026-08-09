import Foundation

/// Thin wrapper over `UserDefaults.standard`.
///
/// The bundle identifier `com.ashatrov.claude-notifier` is the preferences
/// domain the notifier hook scripts read. Changing it breaks them silently:
/// the app would write one domain while the scripts read another, and nothing
/// anywhere would report an error.
///
/// These therefore land in `~/Library/Preferences/com.ashatrov.claude-notifier.plist`
/// where plain `defaults read` finds them. That only holds while the app runs as
/// a real, unsandboxed bundle — see README.
enum Preferences {
    /// What the menu's `Notify [ On | Auto | Off ]` control selects.
    ///
    /// Raw values are strings, not integers, because this domain is a
    /// documented `defaults read` surface: `notificationMode = auto` explains
    /// itself where `1` does not, and reordering the cases cannot silently
    /// reinterpret an existing plist.
    enum NotificationMode: String {
        /// Notify for the whole session, whatever the screen is doing.
        case on
        /// Notify only while every display is asleep.
        case auto
        /// Never notify. Mute.
        case off

        /// Whether a *running* session notifies, given the current screen
        /// state. Deliberately never asks whether a session exists — that is
        /// the caller's half of the rule.
        func notifies(displaysAsleep: Bool) -> Bool {
            switch self {
            case .on: return true
            case .auto: return displaysAsleep
            case .off: return false
            }
        }
    }

    enum Key {
        static let enabled = "enabled"
        static let turnDisplayOffAfterStart = "turnDisplayOffAfterStart"
        static let notificationMode = "notificationMode"
        static let lastCustomDuration = "lastCustomDuration"
    }

    /// Read once by `migrateLegacyNotificationMode()` and then deleted. Kept
    /// private and separate so nothing re-introduces a reader for it.
    private enum LegacyKey {
        static let forceNotifications = "forceNotifications"
    }

    private static let defaults = UserDefaults.standard

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.turnDisplayOffAfterStart: true,
            Key.notificationMode: NotificationMode.auto.rawValue,
            Key.lastCustomDuration: 4.0,
        ])
    }

    /// The flag the notifier hooks gate on:
    ///
    ///     defaults read com.ashatrov.claude-notifier enabled
    ///
    /// True only while a session is running and the mode says yes for the
    /// current screen state.
    static var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    static var turnDisplayOffAfterStart: Bool {
        get { defaults.bool(forKey: Key.turnDisplayOffAfterStart) }
        set { defaults.set(newValue, forKey: Key.turnDisplayOffAfterStart) }
    }

    /// Which of the three notification rules applies. Still requires a session:
    /// `.on` never notifies on its own.
    ///
    /// Set through `UnattendedModeController.setNotificationMode(_:)` so the
    /// change applies right away rather than at the next screen transition.
    ///
    /// An unrecognised raw value falls back to `.auto` rather than trapping —
    /// a hand-edited plist must degrade to the safe rule, never to silence.
    static var notificationMode: NotificationMode {
        get { NotificationMode(rawValue: defaults.string(forKey: Key.notificationMode) ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: Key.notificationMode) }
    }

    /// Maps the pre-tri-state `forceNotifications` flag onto the new mode, once.
    ///
    /// MUST be called *before* `registerDefaults()`. `object(forKey:)` consults
    /// the registration domain as well as the persistent one, so once a default
    /// for `notificationMode` is registered the first guard can never be false
    /// and this becomes a permanent, silent no-op. `forceNotifications` is
    /// likewise no longer registered, so that if the call order is ever reversed
    /// the legacy read returns nil — the worst case is "migration skipped",
    /// not "everyone reset to Auto".
    ///
    /// `object(forKey:)` rather than `bool(forKey:)` because `bool` cannot tell
    /// "never written" from "written false". Both map to `.auto`, so the result
    /// is the same either way; what matters is that a machine which never
    /// touched the old toggle gets nothing written at all, leaving the value to
    /// the registration domain.
    ///
    /// The legacy key is deleted so `defaults read com.ashatrov.claude-notifier`
    /// stops advertising a setting that no longer controls anything. The cost is
    /// that downgrading to an older build reverts that user to non-forced.
    static func migrateLegacyNotificationMode() {
        guard defaults.object(forKey: Key.notificationMode) == nil else { return }
        guard let forced = defaults.object(forKey: LegacyKey.forceNotifications) as? Bool else { return }

        notificationMode = forced ? .on : .auto
        defaults.removeObject(forKey: LegacyKey.forceNotifications)
    }

    /// Writes the effective mode into the plist, so
    ///
    ///     defaults read com.ashatrov.claude-notifier notificationMode
    ///
    /// answers on a machine where the control has never been touched. Same
    /// materialisation `AppDelegate` does for `enabled`, and for the same
    /// reason: this domain is a documented shell-readable surface, and a
    /// registered default lives only in memory.
    ///
    /// MUST run *after* `migrateLegacyNotificationMode()`, whose guard tests
    /// whether this key has ever been written, and after `registerDefaults()`,
    /// so the value written is the registered `.auto` rather than a second copy
    /// of that default spelled out here.
    static func materializeNotificationMode() {
        let mode = notificationMode
        notificationMode = mode
    }

    /// Hours, remembered between uses of the Custom… dialog.
    static var lastCustomDuration: Double {
        get { defaults.double(forKey: Key.lastCustomDuration) }
        set { defaults.set(newValue, forKey: Key.lastCustomDuration) }
    }
}
