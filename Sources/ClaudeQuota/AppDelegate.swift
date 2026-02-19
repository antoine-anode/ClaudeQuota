import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var lastQuota: QuotaInfo?
    private var lastError: String?
    private var isRefreshing = false

    private let normalInterval: TimeInterval = 120   // 2 minutes
    private let highUsageInterval: TimeInterval = 30  // 30 seconds when >=75%
    private let highUsageThreshold: Double = 0.75

    private let launchAgentPath = NSHomeDirectory() + "/Library/LaunchAgents/com.claude.quota.plist"
    private let logPath = "/tmp/claude-quota.log"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        updateDisplay(text: "☁ ...", color: .labelColor)
        refreshQuota()
        scheduleTimer(interval: normalInterval)
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if let q = lastQuota {
            let usageItem = NSMenuItem(
                title: "Usage 5h: \(q.percentUsed)%  —  Relief: ~\(q.estimatedTimeUntilRelief)",
                action: nil, keyEquivalent: ""
            )
            usageItem.isEnabled = false
            menu.addItem(usageItem)

            if q.utilization7d > 0 {
                let weekItem = NSMenuItem(
                    title: "Usage 7j: \(Int(q.utilization7d * 100))%",
                    action: nil, keyEquivalent: ""
                )
                weekItem.isEnabled = false
                menu.addItem(weekItem)
            }

            if let status = q.status {
                let statusMenuItem = NSMenuItem(title: "Status: \(status)", action: nil, keyEquivalent: "")
                statusMenuItem.isEnabled = false
                menu.addItem(statusMenuItem)
            }

            if let fallback = q.fallbackPercentage, fallback > 0 {
                let fbItem = NSMenuItem(
                    title: "Fallback disponible: \(Int(fallback * 100))%",
                    action: nil, keyEquivalent: ""
                )
                fbItem.isEnabled = false
                menu.addItem(fbItem)
            }

            menu.addItem(NSMenuItem.separator())
        }

        if let err = lastError {
            let errItem = NSMenuItem(title: "Erreur: \(err)", action: nil, keyEquivalent: "")
            errItem.isEnabled = false
            menu.addItem(errItem)
            menu.addItem(NSMenuItem.separator())
        }

        let refreshItem = NSMenuItem(title: "Rafraîchir", action: #selector(refreshAction), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let logItem = NSMenuItem(title: "Voir les logs", action: #selector(openLogs), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())

        let launchItem = NSMenuItem(title: "Lancer au démarrage", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = isLaunchAgentInstalled() ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quitter", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Display

    private func updateDisplay(text: String, color: NSColor) {
        guard let button = statusItem.button else { return }
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            ]
        )
        button.attributedTitle = attributed
    }

    // MARK: - Refresh

    private func scheduleTimer(interval: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshQuota()
        }
    }

    private func refreshQuota() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            do {
                let quota = try await QuotaService.shared.fetchQuota()
                await MainActor.run {
                    self.lastQuota = quota
                    self.lastError = nil
                    self.applyQuota(quota)
                    self.isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.updateDisplay(text: "☁ err", color: .systemRed)
                    self.isRefreshing = false
                    self.rebuildMenu()
                    log("Quota fetch error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func applyQuota(_ quota: QuotaInfo) {
        let pct = quota.percentUsed
        let time = quota.estimatedTimeUntilRelief
        let text = "☁ \(pct)% | \(time)"
        let color: NSColor = quota.utilization5h >= 0.80 ? .systemRed : .labelColor

        updateDisplay(text: text, color: color)

        // Adaptive refresh rate
        let interval = quota.utilization5h >= highUsageThreshold ? highUsageInterval : normalInterval
        if refreshTimer?.timeInterval != interval {
            scheduleTimer(interval: interval)
        }

        rebuildMenu()
    }

    // MARK: - Launch at Login (LaunchAgent)

    private func isLaunchAgentInstalled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentPath)
    }

    @objc private func toggleLaunchAtLogin() {
        if isLaunchAgentInstalled() {
            // Unload and remove
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["unload", launchAgentPath]
            try? task.run()
            task.waitUntilExit()
            try? FileManager.default.removeItem(atPath: launchAgentPath)
        } else {
            // Create and load — use the current binary's path
            let execPath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
            let plist: [String: Any] = [
                "Label": "com.claude.quota",
                "ProgramArguments": [execPath],
                "RunAtLoad": true,
                "KeepAlive": true,
                "StandardErrorPath": logPath,
            ]
            let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            FileManager.default.createFile(atPath: launchAgentPath, contents: data)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["load", launchAgentPath]
            try? task.run()
            task.waitUntilExit()
        }
        rebuildMenu()
    }

    // MARK: - Actions

    @objc private func refreshAction() {
        refreshQuota()
    }

    @objc private func openLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
