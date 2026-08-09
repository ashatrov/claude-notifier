import AppKit

/// The menu bar item and its menu.
///
/// The status item shows an icon only — remaining time lives at the top of the
/// dropdown instead, to keep the menu bar footprint as small as possible.
final class StatusBarController: NSObject, NSMenuDelegate {
    private static let presetHours: [Double] = [1, 2, 4, 8, 12]

    /// Segment order, and the only mapping between an index and a mode. Label
    /// and tooltip travel with the mode so reordering here cannot leave a
    /// segment reading "On" while acting as `.off`.
    private static let modes: [(mode: Preferences.NotificationMode, label: String, tooltip: String)] = [
        (.on, "On", "Notify for the whole session"),
        (.auto, "Auto", "Notify only while the screen is off"),
        (.off, "Off", "Never notify"),
    ]

    /// Where an ordinary menu item's *title* starts, measured from the left edge
    /// of a custom item view. No API exposes it and it has moved between macOS
    /// releases, so it is calibrated by eye against the rows above and below.
    /// Keep it in this one place.
    private static let menuTitleInset: CGFloat = 14

    /// The gap after the "Notify" label and the padding after the control.
    /// Named because the constraints and the explicit frame width below both
    /// need them, and a frame that disagrees with the constraints either clips
    /// the last segment or leaves dead menu background beside it.
    private static let modeLabelGap: CGFloat = 8
    private static let modeTrailingPadding: CGFloat = 12

    private let statusItem: NSStatusItem
    private let controller: UnattendedModeController

    /// The live pieces, kept only while the menu is open so they can tick.
    private weak var notificationsItem: NSMenuItem?
    private weak var remainingItem: NSMenuItem?
    private var menuTimer: Timer?

    /// Kept alive so the window keeps its state between openings.
    private var settingsWindow: SettingsWindowController?

    init(controller: UnattendedModeController) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        // Enabled state is set explicitly below rather than inferred.
        menu.autoenablesItems = false
        statusItem.menu = menu

        controller.onStateChange = { [weak self] in self?.updateIcon() }
        updateIcon()
    }

    // MARK: - Icon

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let active = controller.isActive
        let symbol = active ? "cup.and.saucer.fill" : "cup.and.saucer"
        let description = active ? "Claude Notifier Manager, active" : "Claude Notifier Manager, inactive"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
    }

    // MARK: - Menu

    /// macOS 26 attaches a symbol to menu items whose *selector name* looks like
    /// a standard action: anything resembling "settings" or "preferences" gets a
    /// gear. The title is irrelevant — the method name alone decides it.
    ///
    /// That icon reserves an image column for its whole menu section, indenting
    /// that section's titles while the sections above stay put, which knocked
    /// Settings and Quit out of line with everything else.
    ///
    /// Clearing `item.image` does not help: the system runs its own decoration
    /// pass *after* this method returns and paints the gear regardless. The only
    /// reliable fix is to keep those words out of selector names, hence
    /// `showConfigWindow`.
    ///
    /// None of this reaches the notification mode row: a custom-view item has no
    /// title and no action for that pass to key on, and the segmented control's
    /// selector belongs to the control rather than to any menu item. The risk
    /// there is the inverse one — a symbol on a *sibling* reserving the image
    /// column would indent the neighbours while `menuTitleInset` stayed put — so
    /// that row is kept alone in its own section in both menus.
    ///
    /// Rebuilt on every open, so the countdown starts from the real value rather
    /// than a cached one. Called before `menuWillOpen`.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if controller.isActive {
            buildActiveMenu(menu)
        } else {
            buildInactiveMenu(menu)
        }

        addHookWarning(menu)

        menu.addItem(.separator())
        add(menu, "Settings…", #selector(showConfigWindow), key: ",")
        add(menu, "Quit Claude Notifier Manager", #selector(quit), key: "q")
    }

    /// Says something only when the notifier needs attention. A hook that is
    /// installed and current adds no row at all — the menu stays as short as it
    /// has always been.
    ///
    /// Opens Settings rather than installing from here: the install button
    /// belongs next to the provider picker that chooses what gets installed.
    private func addHookWarning(_ menu: NSMenu) {
        let title: String
        switch NotifierHook.state() {
        case .current: return
        case .notInstalled: title = "⚠︎ Install notifier…"
        case .outdated: title = "⚠︎ Update notifier…"
        case .foreign: title = "⚠︎ Unrecognised notifier…"
        }

        menu.addItem(.separator())
        add(menu, title, #selector(showConfigWindow))
    }

    /// Tick the countdown while the menu is on screen. Showing seconds without
    /// this would leave a visibly frozen number under the cursor.
    func menuWillOpen(_ menu: NSMenu) {
        guard controller.isActive else { return }

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshRemaining()
        }
        // Menu tracking blocks the default run loop mode.
        RunLoop.main.add(timer, forMode: .common)
        menuTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        menuTimer?.invalidate()
        menuTimer = nil
        notificationsItem = nil
        remainingItem = nil
    }

    private func refreshRemaining() {
        guard controller.isActive else {
            // The session ended while the menu was open, so the visible items
            // (Stop, Remaining) no longer describe reality. Close it.
            statusItem.menu?.cancelTracking()
            return
        }
        refreshNotificationsLine()
        remainingItem?.title = "Remaining: \(Self.formatRemaining(controller.remaining))"
    }

    /// Shared by the once-a-second tick and by the mode control, which cannot
    /// wait for the next tick — and in the inactive menu never gets one, since
    /// `menuWillOpen` starts no timer there. A no-op when the row is absent.
    private func refreshNotificationsLine() {
        notificationsItem?.title = Self.notificationsStatus()
    }

    private func buildInactiveMenu(_ menu: NSMenu) {
        addHeader(menu, "Claude Notifier Manager")
        menu.addItem(.separator())

        for hours in Self.presetHours {
            let unit = hours == 1 ? "hour" : "hours"
            let item = add(menu, "Awake for \(Self.describe(hours)) \(unit)", #selector(startPreset(_:)))
            item.representedObject = hours
        }

        add(menu, "Custom…", #selector(startCustom))

        menu.addItem(.separator())

        let toggle = add(menu, "Turn display off after start", #selector(toggleDisplayOff))
        toggle.state = Preferences.turnDisplayOffAfterStart ? .on : .off

        // Its own section, so nothing else can ever reserve the image column
        // here and indent the neighbours out from under `menuTitleInset`.
        menu.addItem(.separator())
        menu.addItem(makeNotificationModeItem())
    }

    private func buildActiveMenu(_ menu: NSMenu) {
        addHeader(menu, "Claude Notifier Manager — Active")
        notificationsItem = addHeader(menu, Self.notificationsStatus())
        remainingItem = addHeader(menu, "Remaining: \(Self.formatRemaining(controller.remaining))")
        menu.addItem(.separator())

        menu.addItem(makeNotificationModeItem())

        menu.addItem(.separator())

        // Both items in this section carry a symbol: an image on one of them
        // reserves the image column for the whole section anyway, so a lone icon
        // would leave the other title indented next to empty space.
        add(menu, "Turn Display Off Now", #selector(turnDisplayOffNow), symbol: "display")
        add(menu, "Stop", #selector(stop), symbol: "stop.fill")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "",
                     symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            image?.isTemplate = true
            item.image = image
        } else {
            item.image = nil
        }
        menu.addItem(item)
        return item
    }

    /// The `Notify [ On | Auto | Off ]` row.
    ///
    /// A custom item view is sized from its *frame*, not from its constraints —
    /// `NSMenu` runs no fitting pass — so the frame is set explicitly here from
    /// the children's fitting sizes. Leaving it unset yields a zero-height row.
    ///
    /// The trailing constraint is `greaterThanOrEqualTo`, making that width a
    /// minimum request: when a longer row widens the menu, the extra space lands
    /// to the right of the control as plain menu background rather than
    /// stretching the segments across the whole row.
    private func makeNotificationModeItem() -> NSMenuItem {
        let label = NSTextField(labelWithString: "Notify")
        // 0 means the menu's own size, so this tracks the system menu font
        // instead of hard-coding one. The default `labelColor` is what follows
        // light/dark and Increase Contrast — never bake a colour in here.
        label.font = NSFont.menuFont(ofSize: 0)
        label.translatesAutoresizingMaskIntoConstraints = false

        let control = NSSegmentedControl(
            labels: Self.modes.map(\.label),
            trackingMode: .selectOne,
            target: self,
            action: #selector(notificationModeChanged(_:))
        )
        // controlSize resets the font, so it has to be set first.
        control.controlSize = .small
        control.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        control.segmentStyle = .automatic
        // The getter already falls back to `.auto`, so the lookup can only miss
        // if a mode were left out of `modes` — select the first segment then.
        control.selectedSegment = Self.modes.firstIndex { $0.mode == Preferences.notificationMode } ?? 0
        control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        control.translatesAutoresizingMaskIntoConstraints = false

        // The row is invisible to type-select and arrow keys — inherent to view
        // items — so the control has to carry its own description, and the
        // tooltips replace what the old self-describing title used to say.
        control.setAccessibilityLabel("Notify")
        control.setAccessibilityHelp("On notifies for the whole session. "
            + "Auto notifies only while the screen is off. Off never notifies.")
        for (index, mode) in Self.modes.enumerated() {
            control.setToolTip(mode.tooltip, forSegment: index)
        }

        let container = NSView()
        container.addSubview(label)
        container.addSubview(control)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                           constant: Self.menuTitleInset),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.leadingAnchor.constraint(equalTo: label.trailingAnchor,
                                             constant: Self.modeLabelGap),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.trailingAnchor.constraint(greaterThanOrEqualTo: control.trailingAnchor,
                                                constant: Self.modeTrailingPadding),
        ])
        container.layoutSubtreeIfNeeded()

        let width = Self.menuTitleInset + label.fittingSize.width + Self.modeLabelGap
            + control.fittingSize.width + Self.modeTrailingPadding
        let height = max(control.fittingSize.height, label.fittingSize.height) + 4
        container.frame = NSRect(x: 0, y: 0, width: width, height: height)
        // The menu stretches the view to its own width; nothing else may move.
        container.autoresizingMask = [.width]
        // Otherwise VoiceOver announces an anonymous group, and the label just
        // repeats what the control already says.
        container.setAccessibilityElement(false)
        label.setAccessibilityElement(false)

        // Deliberately no target/action: a view item draws no title and no
        // state, so the control is the only interactive thing in the row.
        // Enabled because `autoenablesItems` is false and a disabled item's
        // view is not documented to keep receiving mouse events.
        let item = NSMenuItem()
        item.view = container
        item.isEnabled = true
        return item
    }

    @discardableResult
    private func addHeader(_ menu: NSMenu, _ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc private func startPreset(_ sender: NSMenuItem) {
        guard let hours = sender.representedObject as? Double else { return }
        controller.start(hours: hours)
    }

    @objc private func startCustom() {
        // An LSUIElement app is not frontmost, so without this the dialog opens
        // behind whatever is.
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Keep Mac awake for:"
        alert.informativeText = "Hours. Decimals are allowed, for example 1.5."
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = Self.describe(Preferences.lastCustomDuration)
        field.alignment = .right
        field.placeholderString = "hours"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let hours = Self.parseHours(field.stringValue), hours > 0 else {
            let error = NSAlert()
            error.messageText = "Enter a number greater than 0."
            error.informativeText = "For example: 4, or 1.5 for ninety minutes."
            error.addButton(withTitle: "OK")
            error.runModal()
            return
        }

        Preferences.lastCustomDuration = hours
        controller.start(hours: hours)
    }

    @objc private func toggleDisplayOff() {
        Preferences.turnDisplayOffAfterStart.toggle()
    }

    /// The menu deliberately stays open: a three-way picker invites correction,
    /// and the "Notifications:" line above is the feedback for the choice.
    ///
    /// `.selectOne` fires this again when the already-selected segment is
    /// clicked. Harmless — the setter is idempotent and the controller dedupes
    /// the write.
    @objc private func notificationModeChanged(_ sender: NSSegmentedControl) {
        guard Self.modes.indices.contains(sender.selectedSegment) else { return }
        // Via the controller, so an active session picks it up immediately.
        controller.setNotificationMode(Self.modes[sender.selectedSegment].mode)
        // Synchronously: menu tracking blocks the default run loop mode, and a
        // one-second lag after a deliberate click reads as a bug.
        refreshNotificationsLine()
    }

    @objc private func turnDisplayOffNow() {
        // Does not touch the session timeout.
        UnattendedModeController.sleepDisplayNow()
    }

    @objc private func stop() {
        controller.stop()
    }

    /// Deliberately not named `openSettings` — see the note above
    /// `menuNeedsUpdate`. macOS decorates menu items by selector name, and
    /// anything containing "settings" or "preferences" gets a gear.
    @objc private func showConfigWindow() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        settingsWindow?.show()
    }

    @objc private func quit() {
        // Cleanup lives in applicationWillTerminate, so quitting and being
        // terminated share one path and `enabled` can never be left set.
        NSApp.terminate(nil)
    }

    // MARK: - Formatting

    /// Reports the flag the hook scripts actually read, with the reason next to
    /// it. Reading the menu means a display is awake, so in Auto this almost
    /// always shows "off" — the reason is what makes that reassuring rather than
    /// alarming. Under Off the reason is you, which is the whole point of
    /// saying so: nothing else in the UI shows that the phone is muted.
    ///
    /// Mute is checked first for readability, not necessity: `.off` can never
    /// reach `enabled == true`. Nothing raises that flag behind the mode's back
    /// — the Test button signals the script through the environment instead of
    /// borrowing it. There is deliberately no "no session" case: this line only ever renders
    /// with a session running, and by then `start()` has already run the
    /// monitor's first poll through `applyNotificationState()`.
    private static func notificationsStatus() -> String {
        let mode = Preferences.notificationMode
        if mode == .off { return "Notifications: 🔕 off — muted" }

        guard Preferences.enabled else { return "Notifications: 🔕 off — screen is on" }
        return mode == .on
            ? "Notifications: 🔔 on — always"
            : "Notifications: 🔔 on — screen is off"
    }

    /// Rounded, not truncated: a 1 hour session must read "1h 0m 0s" the instant
    /// it starts, never "59m 59s".
    private static func formatRemaining(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 { return "\(hours)h \(minutes)m \(seconds)s" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    /// 4.0 → "4", 1.5 → "1.5".
    private static func describe(_ hours: Double) -> String {
        hours == hours.rounded() ? String(Int(hours)) : String(hours)
    }

    private static func parseHours(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed) { return value }
        // Accept a comma decimal separator for non-US keyboard layouts.
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}
