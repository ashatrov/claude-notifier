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

        /// The script shipped in the app bundle, without its `.sh` extension.
        var resourceName: String? {
            switch self {
            case .telegram: return "notify-telegram"
            case .pushover: return "notify-pushover"
            case .unknown: return nil
            }
        }

        /// What the script's own marker line calls this provider.
        var markerName: String? {
            switch self {
            case .telegram: return "telegram"
            case .pushover: return "pushover"
            case .unknown: return nil
            }
        }

        static let installable: [Provider] = [.telegram, .pushover]
    }

    /// What is sitting at `~/.claude/hooks/notifier.sh` right now.
    enum InstallState {
        case notInstalled
        /// Byte-identical to the script this app ships.
        case current(Provider)
        /// Ours, but not the version this app ships.
        case outdated(Provider)
        /// Someone else's script, or hand-written. Never overwrite silently.
        case foreign

        var provider: Provider {
            switch self {
            case .current(let provider), .outdated(let provider): return provider
            case .notInstalled, .foreign: return .unknown
            }
        }
    }

    enum HookError: LocalizedError {
        case notInstalled
        case notExecutable
        case unknownProvider
        case missingCredentials(Provider, [Keychain.Service])
        case launchFailed(String)
        case scriptMissing(Provider)
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "No notifier installed at ~/.claude/hooks/notifier.sh."
            case .notExecutable:
                return "~/.claude/hooks/notifier.sh is not executable. Run: chmod 700 ~/.claude/hooks/notifier.sh"
            case .unknownProvider:
                return "Could not tell which provider ~/.claude/hooks/notifier.sh uses."
            case .missingCredentials(let provider, let services):
                let names = services.map(\.rawValue).joined(separator: ", ")
                return "\(provider.name) is installed but these keychain items are missing: \(names). Save your credentials first."
            case .launchFailed(let message):
                return "Could not run the notifier: \(message)"
            case .scriptMissing(let provider):
                return "The \(provider.name) script is missing from the app bundle. Rebuild with ./build.sh."
            case .installFailed(let message):
                return "Could not write ~/.claude/hooks/notifier.sh: \(message)"
            }
        }
    }

    /// First line of the marker comment every script this repo ships carries.
    private static let markerPrefix = "# claude-notifier:"

    /// Tells the script this run is a test, so it sends whatever `enabled` says.
    /// Must match the name the shipped scripts check.
    private static let testEnvironmentKey = "CLAUDE_NOTIFIER_TEST"

    static let url = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/hooks/notifier.sh")

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// The copy of a provider's script inside this app bundle.
    ///
    /// Nil when the executable runs outside a bundle — straight out of
    /// `.build/`, say — where there are no resources to find.
    static func bundledScript(_ provider: Provider) -> Data? {
        guard let name = provider.resourceName,
              let url = Bundle.main.url(forResource: name, withExtension: "sh")
        else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Identity comes from the marker line, freshness from a byte comparison.
    ///
    /// Comparing bytes rather than a version number means editing a script and
    /// rebuilding is enough to mark every installed copy stale — there is no
    /// separate number to remember to bump.
    static func state() -> InstallState {
        guard let installed = try? Data(contentsOf: url) else { return .notInstalled }

        for provider in Provider.installable where bundledScript(provider) == installed {
            return .current(provider)
        }

        guard let source = String(data: installed, encoding: .utf8) else { return .foreign }

        for provider in Provider.installable {
            guard let marker = provider.markerName else { continue }
            if source.contains("\(markerPrefix) \(marker)") { return .outdated(provider) }
        }

        // Copies installed before the marker existed: fall back to the keychain
        // service names the script has always had to mention.
        if source.contains(Keychain.Service.telegramBotToken.rawValue) { return .outdated(.telegram) }
        if source.contains(Keychain.Service.pushoverUser.rawValue) { return .outdated(.pushover) }

        return .foreign
    }

    static func installedProvider() -> Provider {
        state().provider
    }

    /// Copies a bundled script over `~/.claude/hooks/notifier.sh`.
    ///
    /// Mode 700: it is read by hooks running as this user only, and it is the
    /// mode the README has always asked for.
    static func install(_ provider: Provider) throws {
        guard let script = bundledScript(provider) else { throw HookError.scriptMissing(provider) }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try script.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            throw HookError.installFailed(error.localizedDescription)
        }
    }

    /// The scripts parse hook input with `jq`. Without it they exit 0 in
    /// silence — no notification, and no error anywhere to explain why — so it
    /// is worth saying so up front.
    ///
    /// A login shell, because that is where the user's PATH (Homebrew included)
    /// is set up.
    static var hasJQ: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v jq"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Runs the real hook once.
    ///
    /// Note the notifier scripts always `exit 0` — by design, so a broken
    /// notifier can never block Claude — which means a send failure is
    /// invisible here. Everything checkable is checked up front instead.
    static func sendTest() throws {
        guard isInstalled else { throw HookError.notInstalled }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw HookError.notExecutable }

        let provider = installedProvider()
        guard provider != .unknown else { throw HookError.unknownProvider }

        let missing = provider.requiredServices.filter { !Keychain.exists($0) }
        guard missing.isEmpty else { throw HookError.missingCredentials(provider, missing) }

        let process = Process()
        process.executableURL = url
        process.arguments = ["done"]

        // A second way past the script's gate, rather than raising `enabled`
        // for the duration of the send.
        //
        // `enabled` belongs to the running session: the controller derives it
        // from the session and the screen, and this method blocks on
        // `waitUntilExit()` for as long as the network takes. Borrowing the flag
        // means a session that starts or stops inside that window has its write
        // overwritten on the way out — leaving `enabled` set with no session,
        // and every later Claude hook notifying the phone until the app is
        // relaunched. Signalling out of band makes that unreachable.
        //
        // The notification mode is bypassed either way, deliberately: a test
        // must still send under Off. Proving the chain works is exactly what you
        // want when the phone has been muted.
        var environment = ProcessInfo.processInfo.environment
        environment[Self.testEnvironmentKey] = "1"
        process.environment = environment

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
        let cwd = NSHomeDirectory() + "/Claude Notifier Manager test"
        let payload = ["cwd": cwd]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            inPipe.fileHandleForWriting.write(data)
        }
        inPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()
    }
}
