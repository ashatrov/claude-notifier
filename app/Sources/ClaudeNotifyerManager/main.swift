import AppKit

let app = NSApplication.shared

// NSApplication holds its delegate weakly; this global keeps it alive.
let delegate = AppDelegate()
app.delegate = delegate

// Menu bar only: no Dock icon, no app menu. LSUIElement in Info.plist says the
// same thing, this makes it true even when run outside the bundle.
app.setActivationPolicy(.accessory)

app.run()
