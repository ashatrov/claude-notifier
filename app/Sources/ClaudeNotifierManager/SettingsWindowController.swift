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
    private let installButton = NSButton(title: "Install", target: nil, action: nil)
    private let testButton = NSButton(title: "Send test", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)

    private var provider: Provider {
        Provider(rawValue: providerPicker.selectedSegment) ?? .telegram
    }

    private var hookProvider: NotifierHook.Provider {
        provider == .telegram ? .telegram : .pushover
    }

    /// Looked up once per opening rather than on every refresh: the check runs a
    /// login shell, which is too slow to repeat every time the picker moves.
    private var jqAvailable = true

    // MARK: - Construction

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Notifier Manager Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        window.delegate = self
        window.contentView = buildContentView()
        window.center()

        providerPicker.target = self
        providerPicker.action = #selector(providerChanged)
        fetchChatIDButton.target = self
        fetchChatIDButton.action = #selector(fetchChatID)
        installButton.target = self
        installButton.action = #selector(installNotifier)
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
        root.addArrangedSubview(installButton)

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
        jqAvailable = NotifierHook.hasJQ
        loadFromKeychain()
        refreshHookStatus()
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

    /// Drives both the status line and the install button, so the two can never
    /// disagree about what is on disk.
    private func refreshHookStatus() {
        let state = NotifierHook.state()

        var parts: [String] = []
        switch state {
        case .notInstalled:
            parts.append("⚠︎ No notifier installed at ~/.claude/hooks/notifier.sh")
        case .foreign:
            parts.append("⚠︎ Unrecognised script at ~/.claude/hooks/notifier.sh")
        case .current(let installed), .outdated(let installed):
            parts.append("Hook installed: \(installed.name)")
            if case .outdated = state { parts.append("update available") }
            let configured = installed.requiredServices.allSatisfy { Keychain.exists($0) }
            parts.append(configured ? "credentials saved" : "credentials missing")
        }

        // The scripts pipe every hook payload through jq. Missing, they exit 0
        // without a word, so nothing else here would ever hint at the cause.
        if !jqAvailable { parts.append("⚠︎ jq not found — run: brew install jq") }

        hookLabel.stringValue = parts.joined(separator: " · ")

        installButton.isEnabled = true
        switch state {
        case .notInstalled:
            installButton.title = "Install \(hookProvider.name)"
        case .foreign:
            installButton.title = "Replace…"
        case .current(let installed) where installed == hookProvider:
            installButton.title = "Installed"
            installButton.isEnabled = false
        case .outdated(let installed) where installed == hookProvider:
            installButton.title = "Update"
        case .current, .outdated:
            installButton.title = "Switch to \(hookProvider.name)"
        }
    }

    // MARK: - Actions

    @objc private func providerChanged() {
        telegramRows.isHidden = provider != .telegram
        pushoverRows.isHidden = provider != .pushover
        // The button offers to install whatever the picker points at, so its
        // title has to follow the picker.
        refreshHookStatus()
        resizeToFit()
    }

    /// Writes the picked provider's bundled script over the hook.
    ///
    /// A script we do not recognise is someone's own work, so it is replaced
    /// only after asking. Everything else — missing, stale, other provider —
    /// goes straight through, since the app is the thing that put it there.
    @objc private func installNotifier() {
        if case .foreign = NotifierHook.state(), !confirmReplace() { return }

        do {
            try NotifierHook.install(hookProvider)
            loadFromKeychain()
            refreshHookStatus()
            show(success: "Installed the \(hookProvider.name) notifier at ~/.claude/hooks/notifier.sh")
        } catch {
            show(error: error.localizedDescription)
        }
    }

    private func confirmReplace() -> Bool {
        // An LSUIElement app is not frontmost, so the alert would otherwise open
        // behind whatever is — same reason as the Custom… dialog in the menu.
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Replace the existing notifier?"
        alert.informativeText = """
            ~/.claude/hooks/notifier.sh was not installed by this app. \
            Replacing it discards whatever is there now.
            """
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
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
        refreshHookStatus()
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
