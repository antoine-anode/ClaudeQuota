import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // No dock icon, menu bar only

let delegate = AppDelegate()
app.delegate = delegate

app.run()
