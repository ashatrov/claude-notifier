import Foundation

/// The notifier script Claude Code actually runs.
///
/// The Test button drives *this*, not a Swift reimplementation of the send. A
/// copy of the logic could pass while the real hook fails — wrong keychain item,
/// missing `jq`, a typo in the script. Running the real thing tests the whole
/// chain at once.
enum NotifierHook {
    enum Provider {
        case telegram
        case pushover
        case unknown

        var name: String {
            switch self {
            case .telegram: return "Telegram"
            case .pushover: return "Pushover"
            case .unknown: return "unknown"
            }
        }

        /// Keychain items this provider's script needs to send anything.
        var requiredServices: [Keychain.Service] {
            switch self {
            case .telegram: return [.telegramBotToken, .telegramChatID]
            case .pushover: return [.pushoverUser, .pushoverToken]
            case .unknown: return []
            }
        }
    }

    enum HookError: LocalizedError {
        case notInstalled
        case notExecutable
        case unknownProvider
        case missingCredentials(Provider, [Keychain.Service])
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "No notifier installed at ~/.claude/hooks/notifyer.sh."
            case .notExecutable:
                return "~/.claude/hooks/notifyer.sh is not executable. Run: chmod 700 ~/.claude/hooks/notifyer.sh"
            case .unknownProvider:
                return "Could not tell which provider ~/.claude/hooks/notifyer.sh uses."
            case .missingCredentials(let provider, let services):
                let names = services.map(\.rawValue).joined(separator: ", ")
                return "\(provider.name) is installed but these keychain items are missing: \(names). Save your credentials first."
            case .launchFailed(let message):
                return "Could not run the notifier: \(message)"
            }
        }
    }

    static let url = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/hooks/notifyer.sh")

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Worked out from the keychain service names the script mentions.
    static func installedProvider() -> Provider {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return .unknown }
        if source.contains(Keychain.Service.telegramBotToken.rawValue) { return .telegram }
        if source.contains(Keychain.Service.pushoverUser.rawValue) { return .pushover }
        return .unknown
    }

    /// Runs the real hook once.
    ///
    /// The script's own gate is `enabled`, so it is raised for the duration and
    /// put back afterwards. Note the notifier scripts always `exit 0` — by
    /// design, so a broken notifier can never block Claude — which means a send
    /// failure is invisible here. Everything checkable is checked up front
    /// instead.
    static func sendTest() throws {
        guard isInstalled else { throw HookError.notInstalled }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw HookError.notExecutable }

        let provider = installedProvider()
        guard provider != .unknown else { throw HookError.unknownProvider }

        let missing = provider.requiredServices.filter { !Keychain.exists($0) }
        guard missing.isEmpty else { throw HookError.missingCredentials(provider, missing) }

        let previouslyEnabled = Preferences.enabled
        Preferences.enabled = true
        defer { Preferences.enabled = previouslyEnabled }

        let process = Process()
        process.executableURL = url
        process.arguments = ["done"]

        let inPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw HookError.launchFailed(error.localizedDescription)
        }

        // The script titles the notification after the last path component of
        // `cwd`, so this is what shows up on the phone. The path need not exist.
        let cwd = NSHomeDirectory() + "/Claude Notifyer Manager test"
        let payload = ["cwd": cwd]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            inPipe.fileHandleForWriting.write(data)
        }
        inPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()
    }
}
