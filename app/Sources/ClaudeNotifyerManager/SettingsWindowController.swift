import AppKit

/// Credentials UI, replacing the old `*-credentials-to-keychain.sh` scripts.
///
/// Writes go through `Keychain`, which shells out to `/usr/bin/security` so the
/// items keep the ACL the notifier hook expects.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private enum Provider: Int {
        case telegram = 0
        case pushover = 1
    }

    /// One width for the fields and the wrapping labels, so the window never
    /// changes width — only height, as status text wraps.
    private static let contentWidth: CGFloat = 320

    private let providerPicker = NSSegmentedControl(
        labels: ["Telegram", "Pushover"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    private let botTokenField = NSSecureTextField()
    private let chatIDField = NSTextField()
    private let fetchChatIDButton = NSButton(title: "Get from bot", target: nil, action: nil)

    private let pushoverUserField = NSSecureTextField()
    private let pushoverTokenField = NSSecureTextField()

    private let telegramRows = NSStackView()
    private let pushoverRows = NSStackView()
    private let root = NSStackView()

    private let statusLabel = NSTextField(labelWithString: "")
    private let hookLabel = NSTextField(labelWithString: "")
    private let testButton = NSButton(title: "Send test", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)

    private var provider: Provider {
        Provider(rawValue: providerPicker.selectedSegment) ?? .telegram
    }

    // MARK: - Construction

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Notifyer Manager Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        window.delegate = self
        window.contentView = buildContentView()
        window.center()

        providerPicker.target = self
        providerPicker.action = #selector(providerChanged)
        fetchChatIDButton.target = self
        fetchChatIDButton.action = #selector(fetchChatID)
        testButton.target = self
        testButton.action = #selector(sendTest)
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildContentView() -> NSView {
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        root.addArrangedSubview(labelled("Provider:", providerPicker))

        telegramRows.orientation = .vertical
        telegramRows.alignment = .leading
        telegramRows.spacing = 8
        telegramRows.addArrangedSubview(labelled("Bot token:", botTokenField))

        let chatRow = NSStackView(views: [chatIDField, fetchChatIDButton])
        chatRow.orientation = .horizontal
        chatRow.spacing = 8
        telegramRows.addArrangedSubview(labelled("Chat ID:", chatRow))

        pushoverRows.orientation = .vertical
        pushoverRows.alignment = .leading
        pushoverRows.spacing = 8
        pushoverRows.addArrangedSubview(labelled("User key:", pushoverUserField))
        pushoverRows.addArrangedSubview(labelled("API token:", pushoverTokenField))

        root.addArrangedSubview(telegramRows)
        root.addArrangedSubview(pushoverRows)

        // chatIDField is deliberately not in this list — it gets its own,
        // narrower width below. Two active width constraints would conflict.
        for field in [botTokenField, pushoverUserField, pushoverTokenField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        }
        chatIDField.translatesAutoresizingMaskIntoConstraints = false
        chatIDField.widthAnchor.constraint(equalToConstant: 180).isActive = true

        hookLabel.font = .systemFont(ofSize: 11)
        hookLabel.textColor = .secondaryLabelColor
        wrap(hookLabel, width: Self.contentWidth)
        root.addArrangedSubview(hookLabel)

        statusLabel.font = .systemFont(ofSize: 11)
        wrap(statusLabel, width: Self.contentWidth)
        root.addArrangedSubview(statusLabel)

        let buttons = NSStackView(views: [testButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        root.addArrangedSubview(buttons)

        return root
    }

    /// Makes a label wrap onto as many lines as it needs.
    ///
    /// `preferredMaxLayoutWidth` on its own is not enough: the cell must be told
    /// to wrap, and a real width constraint is needed or the label simply makes
    /// the window wider instead of breaking the line. Low horizontal compression
    /// resistance keeps long text from forcing the window out.
    private func wrap(_ label: NSTextField, width: CGFloat) {
        label.lineBreakMode = .byWordWrapping
        label.usesSingleLineMode = false
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = width
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    /// A caption above a control, so the form reads top to bottom.
    private func labelled(_ caption: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: caption)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [label, control])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }

    // MARK: - Presenting

    func show() {
        loadFromKeychain()
        refreshHookLabel()
        statusLabel.stringValue = ""
        resizeToFit()
        window?.center()

        // An LSUIElement app is never frontmost on its own.
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func loadFromKeychain() {
        // Existing secrets are shown as a placeholder rather than filled in:
        // reading them back would prompt for keychain access on every open.
        let saved = "••••••••"

        botTokenField.stringValue = ""
        botTokenField.placeholderString = Keychain.exists(.telegramBotToken) ? saved : "123456:ABC-DEF..."
        chatIDField.stringValue = Keychain.exists(.telegramChatID) ? (Keychain.read(.telegramChatID) ?? "") : ""
        chatIDField.placeholderString = "123456789"

        pushoverUserField.stringValue = ""
        pushoverUserField.placeholderString = Keychain.exists(.pushoverUser) ? saved : "user key"
        pushoverTokenField.stringValue = ""
        pushoverTokenField.placeholderString = Keychain.exists(.pushoverToken) ? saved : "application API token"

        // Open on whichever provider is actually wired up.
        switch NotifierHook.installedProvider() {
        case .pushover: providerPicker.selectedSegment = Provider.pushover.rawValue
        default: providerPicker.selectedSegment = Provider.telegram.rawValue
        }
        providerChanged()
    }

    private func refreshHookLabel() {
        guard NotifierHook.isInstalled else {
            hookLabel.stringValue = "⚠︎ No notifier installed at ~/.claude/hooks/notifyer.sh"
            return
        }
        let provider = NotifierHook.installedProvider()
        let configured = provider.requiredServices.allSatisfy { Keychain.exists($0) }
        hookLabel.stringValue = configured
            ? "Hook installed: \(provider.name) · credentials saved"
            : "Hook installed: \(provider.name) · credentials missing"
    }

    // MARK: - Actions

    @objc private func providerChanged() {
        telegramRows.isHidden = provider != .telegram
        pushoverRows.isHidden = provider != .pushover
        resizeToFit()
    }

    /// The window is not resizable, so it must be told the size its content
    /// wants — which changes as provider rows are shown and hidden, and as
    /// status text wraps onto more lines.
    ///
    /// Width is pinned by `contentWidth`, so only the height moves. The top-left
    /// corner is restored afterwards because AppKit anchors frames at the
    /// bottom-left, which would otherwise walk the title bar up the screen.
    private func resizeToFit() {
        guard let window else { return }
        root.layoutSubtreeIfNeeded()
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(root.fittingSize)
        window.setFrameTopLeftPoint(topLeft)
    }

    @objc private func save() {
        do {
            switch provider {
            case .telegram:
                let token = botTokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let chatID = chatIDField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

                // Blank means "leave what is already stored", so the placeholder
                // dots are truthful.
                if !token.isEmpty { try Keychain.write(token, to: .telegramBotToken) }
                if !chatID.isEmpty { try Keychain.write(chatID, to: .telegramChatID) }

                guard Keychain.exists(.telegramBotToken), Keychain.exists(.telegramChatID) else {
                    show(error: "Enter both a bot token and a chat ID.")
                    return
                }

            case .pushover:
                let user = pushoverUserField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let appToken = pushoverTokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

                if !user.isEmpty { try Keychain.write(user, to: .pushoverUser) }
                if !appToken.isEmpty { try Keychain.write(appToken, to: .pushoverToken) }

                guard Keychain.exists(.pushoverUser), Keychain.exists(.pushoverToken) else {
                    show(error: "Enter both a user key and an application API token.")
                    return
                }
            }
        } catch {
            show(error: error.localizedDescription)
            return
        }

        loadFromKeychain()
        refreshHookLabel()
        show(success: "Saved to keychain.")
    }

    @objc private func fetchChatID() {
        let typed = botTokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = typed.isEmpty ? Keychain.read(.telegramBotToken) : typed

        guard let token, !token.isEmpty else {
            show(error: "Enter the bot token first.")
            return
        }

        fetchChatIDButton.isEnabled = false
        show(info: "Asking Telegram…")

        Task { @MainActor in
            defer { fetchChatIDButton.isEnabled = true }
            do {
                let username = try await TelegramAPI.botUsername(token: token)
                let chatID = try await TelegramAPI.chatID(token: token)
                chatIDField.stringValue = chatID
                show(success: "Found chat ID \(chatID) for @\(username). Press Save.")
            } catch {
                show(error: error.localizedDescription)
            }
        }
    }

    @objc private func sendTest() {
        do {
            try NotifierHook.sendTest()
            show(success: "Test sent through the real hook. Check your phone.")
        } catch {
            show(error: error.localizedDescription)
        }
    }

    // MARK: - Status line

    private func show(error message: String) {
        setStatus("✗ \(message)", color: .systemRed)
    }

    private func show(success message: String) {
        setStatus("✓ \(message)", color: .systemGreen)
    }

    private func show(info message: String) {
        setStatus(message, color: .secondaryLabelColor)
    }

    /// Resizes after every change: the label wraps to a new number of lines, and
    /// the window is not resizable, so it has to be told the new height.
    private func setStatus(_ message: String, color: NSColor) {
        statusLabel.textColor = color
        statusLabel.stringValue = message
        resizeToFit()
    }
}
