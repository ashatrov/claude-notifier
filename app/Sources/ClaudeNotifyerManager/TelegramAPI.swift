import Foundation

/// The one thing the app cannot do without talking to Telegram: turn a bot
/// token into a chat ID. This mirrors what the old
/// `telegram-credentials-to-keychain.sh` did with `curl` and `jq`.
///
/// Sending messages stays in the notifier scripts. The app never does that.
enum TelegramAPI {
    enum APIError: LocalizedError {
        case badToken
        case noMessages
        case transport(String)
        case api(String)

        var errorDescription: String? {
            switch self {
            case .badToken:
                return "Telegram did not accept that bot token."
            case .noMessages:
                return "No message found. Send /start to your bot, then try again."
            case .transport(let message):
                return "Could not reach Telegram: \(message)"
            case .api(let message):
                return "Telegram said: \(message)"
            }
        }
    }

    /// Confirms the token works and returns the bot's @username, so the user
    /// knows which bot to message.
    static func botUsername(token: String) async throws -> String {
        let json = try await call(token: token, method: "getMe")
        guard let result = json["result"] as? [String: Any],
              let username = result["username"] as? String
        else { throw APIError.badToken }
        return username
    }

    /// Reads the most recent incoming message and returns its chat ID.
    static func chatID(token: String) async throws -> String {
        let json = try await call(token: token, method: "getUpdates")
        guard let updates = json["result"] as? [[String: Any]] else {
            throw APIError.noMessages
        }

        // Newest first: the user may have messaged the bot before.
        for update in updates.reversed() {
            let message = (update["message"] ?? update["edited_message"]) as? [String: Any]
            if let chat = message?["chat"] as? [String: Any], let id = chat["id"] {
                if let number = id as? Int { return String(number) }
                if let text = id as? String { return text }
            }
        }
        throw APIError.noMessages
    }

    private static func call(token: String, method: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/\(method)") else {
            throw APIError.badToken
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.api("unexpected response")
        }

        guard json["ok"] as? Bool == true else {
            if let description = json["description"] as? String {
                // 401 on a bad token; say so plainly rather than echoing it.
                throw (json["error_code"] as? Int == 401) ? APIError.badToken : APIError.api(description)
            }
            throw APIError.badToken
        }

        return json
    }
}
