import Foundation

/// Keychain access via `/usr/bin/security`, deliberately not the native
/// `SecItem` API.
///
/// Keychain items carry an ACL naming the code allowed to read them. The
/// notifier hook reads these with `security find-generic-password -w`, so the
/// items must be *written* by `security` too. Writing them natively would make
/// the app the trusted party and every hook run would raise a GUI "allow
/// access?" dialog — headless, while the display is asleep, exactly when nobody
/// can click it.
enum Keychain {
    enum Service: String, CaseIterable {
        case telegramBotToken = "claude-telegram-bot-token"
        case telegramChatID = "claude-telegram-chat-id"
        case pushoverUser = "claude-pushover-user"
        case pushoverToken = "claude-pushover-token"
    }

    enum KeychainError: LocalizedError {
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let message):
                return message.isEmpty ? "Keychain write failed." : message
            }
        }
    }

    private static let securityTool = URL(fileURLWithPath: "/usr/bin/security")

    private static var account: String { NSUserName() }

    /// True if the item exists. Reads metadata only, which is not ACL-guarded,
    /// so this never prompts.
    static func exists(_ service: Service) -> Bool {
        run(["find-generic-password", "-a", account, "-s", service.rawValue]).status == 0
    }

    static func read(_ service: Service) -> String? {
        let result = run(["find-generic-password", "-a", account, "-s", service.rawValue, "-w"])
        guard result.status == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// `-U` updates in place, preserving the existing item's ACL.
    ///
    /// The secret goes in on stdin rather than as an argument, so it never
    /// appears in `ps`. `security` asks for it twice (enter, then retype), so it
    /// must be written twice — feeding it once stores an empty password.
    static func write(_ value: String, to service: Service) throws {
        let result = run(
            ["add-generic-password", "-U", "-a", account, "-s", service.rawValue, "-w"],
            stdin: "\(value)\n\(value)\n"
        )
        guard result.status == 0 else {
            throw KeychainError.commandFailed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    @discardableResult
    static func delete(_ service: Service) -> Bool {
        run(["delete-generic-password", "-a", account, "-s", service.rawValue]).status == 0
    }

    // MARK: - Process

    private static func run(_ arguments: [String], stdin: String? = nil) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = securityTool
        process.arguments = arguments

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe

        let inPipe = Pipe()
        process.standardInput = inPipe

        do {
            try process.run()
        } catch {
            return (1, "Could not run /usr/bin/security: \(error.localizedDescription)")
        }

        if let stdin {
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
        }
        inPipe.fileHandleForWriting.closeFile()

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
