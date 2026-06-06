import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, PanelActions {
    private let store = SessionStore()
    private lazy var engine = StatsEngine(store: store)
    private lazy var monitor = KeystrokeMonitor(stats: engine)
    private lazy var panel = RibbonPanel(engine: engine)
    private var statusItem: NSStatusItem!
    private var statusTimer: Timer?

    private let d = UserDefaults.standard
    private enum K {
        static let goal = "dailyGoal", idle = "idleThreshold", liveWPM = "showLiveWPM"
        static let dock = "showDock", autostart = "autostart", launch = "launchAtLogin"
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        registerDefaults()
        engine.idleThreshold = d.double(forKey: K.idle)

        if let icon = Asset.image("AppIcon") { NSApp.applicationIconImage = icon }
        NSApp.setActivationPolicy(d.bool(forKey: K.dock) ? .regular : .accessory)
        buildMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = Asset.image("RibbonIcon") {
                img.size = NSSize(width: img.size.height > 0 ? 19 * img.size.width / img.size.height : 19, height: 19)
                img.isTemplate = false
                button.image = img
                button.imagePosition = .imageLeft
            } else {
                button.title = "mercury"
            }
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.target = self
            button.action = #selector(statusClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        panel.actions = self

        if d.bool(forKey: K.autostart) { startSessionFlow(silent: true) }

        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatusTitle()
        }
        updateStatusTitle()
    }

    private func registerDefaults() {
        d.register(defaults: [
            K.goal: 1500, K.idle: 3.0, K.liveWPM: true,
            K.dock: true, K.autostart: false, K.launch: false
        ])
    }

    // MARK: status interaction

    @objc private func statusClick(_ sender: NSStatusBarButton) {
        let ev = NSApp.currentEvent
        let rightish = ev?.type == .rightMouseUp || (ev?.modifierFlags.contains(.control) ?? false)
        if rightish { showSettingsMenu(relativeTo: sender) }
        else { panel.toggle(from: sender) }
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        if engine.isActive && d.bool(forKey: K.liveWPM) {
            button.title = "  " + Fmt.wpm(engine.snapshot().liveWPM)
        } else {
            button.title = ""
        }
    }

    // MARK: session

    private func startSessionFlow(silent: Bool = false) {
        if monitor.hasPermission() {
            engine.startSession()
            _ = monitor.start()
            updateStatusTitle(); panel.refresh()
        } else {
            monitor.requestPermission()
            if !silent { showPermissionAlert() }
        }
    }
    private func stopSession() {
        engine.stopSession(); monitor.stop()
        updateStatusTitle(); panel.refresh()
    }

    private func showPermissionAlert() {
        let a = NSAlert()
        a.messageText = "Enable Input Monitoring"
        a.informativeText = "Mercury counts keystrokes (never their content) to measure typing speed. "
            + "Turn on Mercury under Input Monitoring, then relaunch the app."
        a.addButton(withTitle: "Open Settings")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: PanelActions

    func panelToggleSession() {
        if engine.isActive { stopSession() } else { startSessionFlow() }
        updateStatusTitle()
    }
    func panelIsSessionActive() -> Bool { engine.isActive }
    func panelDailyGoal() -> Int { max(1, d.integer(forKey: K.goal)) }
    func panelShowSettings(relativeTo view: NSView) {
        let menu = buildSettingsMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 6), in: view)
    }
    private func showSettingsMenu(relativeTo button: NSStatusBarButton) {
        let menu = buildSettingsMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    // MARK: settings menu

    private func buildSettingsMenu() -> NSMenu {
        let m = NSMenu()
        let toggle = NSMenuItem(title: engine.isActive ? "Stop Session" : "Start Session",
                                action: #selector(menuToggleSession), keyEquivalent: "")
        toggle.target = self; m.addItem(toggle)
        let reset = NSMenuItem(title: "Reset Session", action: #selector(menuResetSession), keyEquivalent: "")
        reset.target = self; m.addItem(reset)
        m.addItem(.separator())

        let goalItem = NSMenuItem(title: "Daily Goal", action: nil, keyEquivalent: "")
        let goalMenu = NSMenu()
        for v in [750, 1000, 1500, 2000, 3000, 5000] {
            let it = NSMenuItem(title: "\(Fmt.int(v)) words", action: #selector(setGoal(_:)), keyEquivalent: "")
            it.target = self; it.tag = v; it.state = (panelDailyGoal() == v) ? .on : .off
            goalMenu.addItem(it)
        }
        goalItem.submenu = goalMenu; m.addItem(goalItem)

        let idleItem = NSMenuItem(title: "Idle Timeout", action: nil, keyEquivalent: "")
        let idleMenu = NSMenu()
        for v in [2, 3, 5, 10] {
            let it = NSMenuItem(title: "\(v)s", action: #selector(setIdle(_:)), keyEquivalent: "")
            it.target = self; it.tag = v
            it.state = (Int(d.double(forKey: K.idle).rounded()) == v) ? .on : .off
            idleMenu.addItem(it)
        }
        idleItem.submenu = idleMenu; m.addItem(idleItem)
        m.addItem(.separator())

        m.addItem(check("Live WPM in Menu Bar", K.liveWPM, #selector(toggleLiveWPM)))
        m.addItem(check("Show Dock Icon", K.dock, #selector(toggleDock)))
        m.addItem(check("Start Tracking at Launch", K.autostart, #selector(toggleAutostart)))
        if #available(macOS 13.0, *) {
            m.addItem(check("Launch Mercury at Login", K.launch, #selector(toggleLaunch)))
        }
        m.addItem(.separator())

        let resetAll = NSMenuItem(title: "Reset All-Time Stats\u{2026}", action: #selector(menuResetAll), keyEquivalent: "")
        resetAll.target = self; m.addItem(resetAll)
        let about = NSMenuItem(title: "About Mercury", action: #selector(showAbout), keyEquivalent: "")
        about.target = self; m.addItem(about)
        m.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Mercury", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        m.addItem(quit)
        return m
    }

    private func check(_ title: String, _ key: String, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self; it.state = d.bool(forKey: key) ? .on : .off
        return it
    }

    @objc private func menuToggleSession() { panelToggleSession() }
    @objc private func menuResetSession() { engine.resetSession(); panel.refresh(); updateStatusTitle() }
    @objc private func setGoal(_ s: NSMenuItem) { d.set(s.tag, forKey: K.goal); panel.refresh() }
    @objc private func setIdle(_ s: NSMenuItem) {
        d.set(Double(s.tag), forKey: K.idle); engine.idleThreshold = Double(s.tag)
    }
    @objc private func toggleLiveWPM() { d.set(!d.bool(forKey: K.liveWPM), forKey: K.liveWPM); updateStatusTitle() }
    @objc private func toggleDock() {
        let v = !d.bool(forKey: K.dock); d.set(v, forKey: K.dock)
        NSApp.setActivationPolicy(v ? .regular : .accessory)
    }
    @objc private func toggleAutostart() { d.set(!d.bool(forKey: K.autostart), forKey: K.autostart) }
    @objc private func toggleLaunch() {
        guard #available(macOS 13.0, *) else { return }
        let v = !d.bool(forKey: K.launch); d.set(v, forKey: K.launch)
        do { if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { NSLog("launch-at-login error: \(error)") }
    }
    @objc private func menuResetAll() {
        let a = NSAlert()
        a.messageText = "Reset all-time stats?"
        a.informativeText = "This permanently clears totals, daily history, and test results."
        a.addButton(withTitle: "Reset"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { engine.resetAllTime(); panel.refresh() }
    }
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "Local-only typing meter.\nKeystroke counts never leave your Mac.",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Mercury",
            .applicationVersion: "2.0",
            .credits: credits
        ])
    }

    // MARK: lifecycle

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let b = statusItem?.button { panel.show(from: b) }
        return true
    }
    func applicationWillTerminate(_ note: Notification) {
        if engine.isActive { engine.stopSession() } else { engine.persist() }
        monitor.stop()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Mercury", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Mercury", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Mercury", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}
