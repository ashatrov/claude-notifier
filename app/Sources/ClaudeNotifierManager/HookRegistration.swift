import Foundation

/// Whether Claude Code is actually wired to call the notifier.
///
/// `NotifierHook` only knows the script is on disk. Send test runs that script
/// directly, so it passes even when `~/.claude/settings.json` has lost its
/// `hooks` block and Claude Code never runs it — Settings said "installed"
/// while no notification could ever arrive. This closes that gap.
///
/// Read-only: the app never writes the user's settings file. Deliberately
/// simple, too — an event counts once any of its hooks mentions the script, so
/// hooks from other plugins and apps never trigger a warning, and matchers and
/// arguments are left to the user.
///
/// Foundation only, so `make test` can compile it on its own.
enum HookRegistration {
    /// The events `claude-settings-file-part.json` registers, in its order.
    static let events = ["PreToolUse", "PermissionRequest", "Elicitation", "Notification", "StopFailure", "Stop"]

    /// Matches `$HOME/…`, `~/…` and absolute spellings alike.
    static let commandMarker = ".claude/hooks/notifier.sh"

    static let settingsURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/settings.json")

    enum Status: Equatable {
        case registered
        /// In `events` order, never empty.
        case missing([String])
        case allHooksDisabled
        case unreadable

        var warning: String? {
            switch self {
            case .registered:
                return nil
            case .missing(let missing) where missing == HookRegistration.events:
                return "⚠︎ No hooks in ~/.claude/settings.json"
            case .missing(let missing):
                return "⚠︎ Not registered in ~/.claude/settings.json: \(missing.joined(separator: ", "))"
            case .allHooksDisabled:
                return "⚠︎ All hooks disabled in ~/.claude/settings.json"
            case .unreadable:
                return "⚠︎ Could not read ~/.claude/settings.json"
            }
        }
    }

    /// `nil` means the file does not exist. Any shape this does not expect
    /// counts as "not registered" for that event, never as an error: the file
    /// is hand-edited, and a warning is the most this check should ever cause.
    static func status(settings data: Data?) -> Status {
        guard let data else { return .missing(events) }

        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .unreadable
        }

        if root["disableAllHooks"] as? Bool == true { return .allHooksDisabled }

        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let missing = events.filter { event in
            let entries = hooks[event] as? [Any] ?? []
            return !entries.contains { entry in
                let commands = ((entry as? [String: Any])?["hooks"] as? [Any]) ?? []
                return commands.contains { command in
                    ((command as? [String: Any])?["command"] as? String)?.contains(commandMarker) == true
                }
            }
        }

        return missing.isEmpty ? .registered : .missing(missing)
    }

    static func current() -> Status {
        do {
            return status(settings: try Data(contentsOf: settingsURL))
        } catch CocoaError.fileReadNoSuchFile {
            return status(settings: nil)
        } catch {
            return .unreadable
        }
    }
}
