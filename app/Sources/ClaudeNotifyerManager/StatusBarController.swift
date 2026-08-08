import AppKit

/// The menu bar item and its menu.
///
/// The status item shows an icon only — remaining time lives at the top of the
/// dropdown instead, to keep the menu bar footprint as small as possible.
final class StatusBarController: NSObject, NSMenuDelegate {
    private static let presetHours: [Double] = [1, 2, 4, 8, 10]

    private let statusItem: NSStatusItem
    private let controller: UnattendedModeController

    /// The two live rows, kept only while the menu is open so they can tick.
    private weak var notificationsItem: NSMenuItem?
    private weak var remainingItem: NSMenuItem?
    private var menuTimer: Timer?

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
        let description = active ? "Claude Notifyer Manager, active" : "Claude Notifyer Manager, inactive"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
    }

    // MARK: - Menu

    /// Rebuilt on every open, so the countdown starts from the real value rather
    /// than a cached one. Called before `menuWillOpen`.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if controller.isActive {
            buildActiveMenu(menu)
        } else {
            buildInactiveMenu(menu)
        }

        menu.addItem(.separator())
        add(menu, "Quit Claude Notifyer Manager", #selector(quit), key: "q")
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
        notificationsItem?.title = Self.notificationsStatus()
        remainingItem?.title = "Remaining: \(Self.formatRemaining(controller.remaining))"
    }

    private func buildInactiveMenu(_ menu: NSMenu) {
        addHeader(menu, "Claude Notifyer Manager")
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

        let force = add(menu, "Force notifications", #selector(toggleForceNotifications))
        force.state = Preferences.forceNotifications ? .on : .off
    }

    private func buildActiveMenu(_ menu: NSMenu) {
        addHeader(menu, "Claude Notifyer Manager — Active")
        notificationsItem = addHeader(menu, Self.notificationsStatus())
        remainingItem = addHeader(menu, "Remaining: \(Self.formatRemaining(controller.remaining))")
        menu.addItem(.separator())

        let force = add(menu, "Force notifications", #selector(toggleForceNotifications))
        force.state = Preferences.forceNotifications ? .on : .off

        menu.addItem(.separator())

        add(menu, "Turn Display Off Now", #selector(turnDisplayOffNow))
        add(menu, "Stop", #selector(stop))
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
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

    @objc private func toggleForceNotifications() {
        // Via the controller, so an active session picks it up immediately.
        controller.setForceNotifications(!Preferences.forceNotifications)
    }

    @objc private func turnDisplayOffNow() {
        // Does not touch the session timeout.
        UnattendedModeController.sleepDisplayNow()
    }

    @objc private func stop() {
        controller.stop()
    }

    @objc private func quit() {
        // Cleanup lives in applicationWillTerminate, so quitting and being
        // terminated share one path and `enabled` can never be left set.
        NSApp.terminate(nil)
    }

    // MARK: - Formatting

    /// Reports the flag the hook scripts actually read, with the reason next to
    /// it. Reading the menu means a display is awake, so in practice this almost
    /// always shows "off" — the reason is what makes that reassuring rather than
    /// alarming.
    private static func notificationsStatus() -> String {
        guard Preferences.enabled else { return "Notifications: 🔕 off — screen is on" }
        return Preferences.forceNotifications
            ? "Notifications: 🔔 on — forced"
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
