import AppKit

protocol PanelActions: AnyObject {
    func panelToggleSession()
    func panelIsSessionActive() -> Bool
    func panelDailyGoal() -> Int
    func panelShowSettings(relativeTo view: NSView)
}

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class Chip: NSButton {
    init(_ t: String) { super.init(frame: .zero); build(t) }
    required init?(coder: NSCoder) { fatalError() }
    private func build(_ t: String) {
        isBordered = false; wantsLayer = true; bezelStyle = .regularSquare
        layer?.cornerRadius = 7
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        set(t, selected: false)
    }
    func set(_ t: String, selected: Bool) {
        let para = NSMutableParagraphStyle(); para.alignment = .center
        attributedTitle = NSAttributedString(string: t.uppercased(), attributes: [
            .font: F.mono(11, .medium),
            .foregroundColor: selected ? Theme.bg : Theme.muted,
            .kern: 0.8,
            .paragraphStyle: para])
        layer?.backgroundColor = (selected ? Theme.chrome : NSColor.clear).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (selected ? Theme.chrome : Theme.stroke).cgColor
    }
}

private final class Dot: NSView {
    var on = false { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 7, height: 7) }
    override func draw(_ dirty: NSRect) {
        let d = min(bounds.width, bounds.height)
        let rect = NSRect(x: (bounds.width - d)/2, y: (bounds.height - d)/2, width: d, height: d).insetBy(dx: 1, dy: 1)
        (on ? Theme.chromeHi : Theme.faint).setFill()
        NSBezierPath(ovalIn: rect).fill()
    }
}

final class RibbonPanel: NSObject, NSWindowDelegate {
    weak var actions: PanelActions?
    private let engine: StatsEngine
    private let window: KeyWindow

    // header / live
    private let logoView = NSImageView()
    private let dot = Dot()
    private let startBtn = NSButton()
    private let bigWPM = NSTextField(labelWithString: "—")
    private let liveCap = NSTextField(labelWithString: "wpm")
    private let avgVal = NSTextField(labelWithString: "—")
    private let burstVal = NSTextField(labelWithString: "—")
    private let wordsVal = NSTextField(labelWithString: "—")
    private let timeVal = NSTextField(labelWithString: "—")

    // tabs
    private var tabButtons: [NSButton] = []
    private var currentTab = 0
    private let bodyContainer = NSView()
    private let nowBody = NSStackView()
    private let todayBody = NSStackView()
    private let statsBody = NSStackView()
    private let BODY_H: CGFloat = 270

    // NOW: test + session graph
    private var chips: [Chip] = []
    private let modesForTags: [TestMode] = [.time(15), .time(30), .time(60), .words(25)]
    private var selectedMode: TestMode = .time(30)
    private let test = TypingTestView()
    private let testWPM = NSTextField(labelWithString: "—")
    private let testAcc = NSTextField(labelWithString: "—")
    private let testTimer = NSTextField(labelWithString: "—")
    private let sessionSpark = SparklineView()
    private var liveSamples: [Double] = []
    private var wasActive = false

    // TODAY: goal + rhythm
    private let todayVal = NSTextField(labelWithString: "—")
    private let bar = BarView()
    private let streakLbl = NSTextField(labelWithString: "streak 0d")
    private let bestLbl = NSTextField(labelWithString: "best —")
    private let rhythm = BarsView()

    // STATS: activity + records + history
    private let heat = HeatmapView()
    private let recBest15 = NSTextField(labelWithString: "—")
    private let recBest30 = NSTextField(labelWithString: "—")
    private let recBest60 = NSTextField(labelWithString: "—")
    private let recBest25 = NSTextField(labelWithString: "—")
    private let summaryLbl = NSTextField(labelWithString: "")
    private let spark = SparklineView()
    private let recentList = NSStackView()

    // FUN: playful equivalences + extra graphs
    private let funBody = NSStackView()
    private let rankLbl = NSTextField(labelWithString: "")
    private let novelsVal = NSTextField(labelWithString: "—")
    private let pagesVal = NSTextField(labelWithString: "—")
    private let tweetsVal = NSTextField(labelWithString: "—")
    private let mileVal = NSTextField(labelWithString: "—")
    private let dist = BarsView()
    private let week = BarsView()

    private let allTimeLbl = NSTextField(labelWithString: "")

    private var globalMon: Any?
    private var localMon: Any?
    private var refreshTimer: Timer?

    private let INNER: CGFloat = 308

    init(engine: StatsEngine) {
        self.engine = engine
        window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 520),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        configureWindow()
        buildContent()
        wireTest()
    }

    private func configureWindow() {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.isMovable = false
        window.delegate = self
        window.hidesOnDeactivate = false
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = Theme.bg.cgColor
        card.layer?.cornerRadius = 14
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = Theme.stroke.cgColor
        window.contentView = card
    }

    // MARK: builders

    private func style(_ l: NSTextField, _ f: NSFont, _ c: NSColor, _ a: NSTextAlignment = .left) {
        l.font = f; l.textColor = c; l.alignment = a; l.lineBreakMode = .byClipping
    }
    private func setMicro(_ l: NSTextField, _ s: String, _ c: NSColor, _ a: NSTextAlignment = .left) {
        l.attributedStringValue = TypeStyle.micro(s, c, size: 10, kern: 1.1, align: a)
    }
    private func rankFor(_ wpm: Double, _ meaningful: Bool) -> String {
        guard meaningful, wpm > 0 else { return "warming up" }
        switch wpm {
        case ..<25:  return "hunt & peck"
        case ..<40:  return "casual"
        case ..<55:  return "steady hands"
        case ..<70:  return "touch typist"
        case ..<85:  return "fast fingers"
        case ..<100: return "speed demon"
        case ..<120: return "keyboard warrior"
        default:     return "ludicrous speed"
        }
    }
    private func pctStr(_ p: Double) -> String {
        if p >= 100 { return Fmt.int(Int(p)) + "%" }
        if p >= 10  { return String(format: "%.1f%%", p) }
        return String(format: "%.2f%%", p)
    }
    private func microCap(_ s: String, _ c: NSColor = Theme.muted) -> NSTextField {
        let l = NSTextField(labelWithAttributedString: TypeStyle.micro(s, c, size: 9, kern: 1.4))
        l.lineBreakMode = .byClipping
        return l
    }
    private func tile(_ value: NSTextField, _ key: String) -> NSView {
        style(value, F.mono(13, .regular), Theme.text)
        let k = NSTextField(labelWithAttributedString: TypeStyle.micro(key, Theme.muted))
        k.lineBreakMode = .byClipping
        let st = NSStackView(views: [value, k])
        st.orientation = .vertical; st.alignment = .leading; st.spacing = 2
        return st
    }
    private func divider() -> NSView {
        let v = NSView(); v.wantsLayer = true
        v.layer?.backgroundColor = Theme.stroke.withAlphaComponent(0.55).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        v.widthAnchor.constraint(equalToConstant: INNER).isActive = true
        return v
    }
    private func iconButton(_ glyph: String, _ sel: Selector) -> NSButton {
        let b = NSButton(); b.isBordered = false; b.bezelStyle = .regularSquare
        b.attributedTitle = NSAttributedString(string: glyph, attributes: [
            .font: F.sans(13), .foregroundColor: Theme.muted])
        b.target = self; b.action = sel
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 22).isActive = true
        b.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return b
    }
    private func setPill(_ b: NSButton, _ text: String) {
        let para = NSMutableParagraphStyle(); para.alignment = .center
        b.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: F.mono(11.5, .medium), .foregroundColor: Theme.chrome, .paragraphStyle: para])
    }
    private func tabButton(_ title: String, _ idx: Int) -> NSButton {
        let b = NSButton(); b.isBordered = false; b.bezelStyle = .regularSquare
        b.tag = idx; b.target = self; b.action = #selector(pickTab(_:))
        b.translatesAutoresizingMaskIntoConstraints = false
        b.attributedTitle = TypeStyle.micro(title, idx == 0 ? Theme.chrome : Theme.faint, size: 9.5, kern: 1.6)
        return b
    }
    private func recordRow(_ caption: String, _ value: NSTextField) -> NSView {
        let k = microCap(caption)
        style(value, F.mono(12, .regular), Theme.text, .right)
        let sp = NSView(); sp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [k, sp, value])
        row.orientation = .horizontal; row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: INNER).isActive = true
        return row
    }
    private func setupBody(_ st: NSStackView, _ views: [NSView]) {
        views.forEach { st.addArrangedSubview($0) }
        st.orientation = .vertical; st.alignment = .leading; st.spacing = 8
        st.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(st)
        NSLayoutConstraint.activate([
            st.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            st.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            st.widthAnchor.constraint(equalToConstant: INNER),
        ])
    }

    private func buildContent() {
        guard let card = window.contentView else { return }

        // ---- header ----
        if let img = Asset.image("RibbonIcon") {
            logoView.image = img
            logoView.imageScaling = .scaleProportionallyUpOrDown
            let aspect = img.size.height > 0 ? img.size.width / img.size.height : 1
            logoView.translatesAutoresizingMaskIntoConstraints = false
            logoView.heightAnchor.constraint(equalToConstant: 18).isActive = true
            logoView.widthAnchor.constraint(equalToConstant: 18 * aspect).isActive = true
        }
        let wordmark = NSTextField(labelWithAttributedString: NSAttributedString(
            string: "mercury", attributes: [.font: F.sans(13, .semibold),
                                            .foregroundColor: Theme.text, .kern: 0.8]))
        wordmark.lineBreakMode = .byClipping
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 7).isActive = true
        let hSpacer = NSView(); hSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        startBtn.isBordered = false; startBtn.wantsLayer = true; startBtn.bezelStyle = .regularSquare
        startBtn.layer?.cornerRadius = 7
        startBtn.layer?.backgroundColor = Theme.card.cgColor
        startBtn.layer?.borderWidth = 1; startBtn.layer?.borderColor = Theme.stroke.cgColor
        startBtn.translatesAutoresizingMaskIntoConstraints = false
        startBtn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        startBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        setPill(startBtn, "start"); startBtn.target = self; startBtn.action = #selector(toggleStart)
        let gear = iconButton("\u{2699}\u{FE0E}", #selector(showGear))
        let header = NSStackView(views: [logoView, wordmark, dot, hSpacer, startBtn, gear])
        header.orientation = .horizontal; header.alignment = .centerY; header.spacing = 8
        header.setCustomSpacing(6, after: wordmark)

        // ---- live ----
        style(bigWPM, F.mono(38, .regular), Theme.text)
        style(liveCap, F.sans(11), Theme.muted)
        let liveRow = NSStackView(views: [bigWPM, liveCap])
        liveRow.orientation = .horizontal; liveRow.alignment = .lastBaseline; liveRow.spacing = 8

        let miniRow = NSStackView(views: [tile(avgVal, "avg"), tile(burstVal, "burst"),
                                          tile(wordsVal, "words"), tile(timeVal, "active")])
        miniRow.orientation = .horizontal; miniRow.distribution = .fillEqually; miniRow.spacing = 6

        // ---- tab bar ----
        tabButtons = [tabButton("now", 0), tabButton("today", 1), tabButton("stats", 2), tabButton("fun", 3)]
        let tabSpacer = NSView(); tabSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        var tabViews: [NSView] = tabButtons; tabViews.append(tabSpacer)
        let tabRow = NSStackView(views: tabViews)
        tabRow.orientation = .horizontal; tabRow.alignment = .centerY; tabRow.spacing = 16

        // ---- NOW body ----
        for (i, m) in modesForTags.enumerated() {
            let c = Chip(m.label); c.tag = i; c.target = self; c.action = #selector(pickChip(_:))
            chips.append(c)
        }
        let chipSpacer = NSView(); chipSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let restart = iconButton("\u{21BB}", #selector(restartTest))
        var testHeaderViews: [NSView] = chips
        testHeaderViews.append(chipSpacer); testHeaderViews.append(restart)
        let testHeader = NSStackView(views: testHeaderViews)
        testHeader.orientation = .horizontal; testHeader.alignment = .centerY; testHeader.spacing = 6

        test.wantsLayer = true
        test.layer?.backgroundColor = Theme.card.cgColor
        test.layer?.cornerRadius = 7
        test.layer?.borderWidth = 1
        test.layer?.borderColor = Theme.stroke.cgColor
        test.translatesAutoresizingMaskIntoConstraints = false
        test.heightAnchor.constraint(equalToConstant: 92).isActive = true

        let testTiles = NSStackView(views: [tile(testWPM, "wpm"), tile(testAcc, "acc"), tile(testTimer, "time")])
        testTiles.orientation = .horizontal; testTiles.distribution = .fillEqually; testTiles.spacing = 6

        let sessionCap = microCap("session")
        sessionSpark.translatesAutoresizingMaskIntoConstraints = false
        sessionSpark.heightAnchor.constraint(equalToConstant: 46).isActive = true
        setupBody(nowBody, [testHeader, test, testTiles, sessionCap, sessionSpark])

        // ---- TODAY body ----
        let todayKey = microCap("today", Theme.muted)
        style(todayVal, F.mono(11.5), Theme.text, .right)
        let todaySpacer = NSView(); todaySpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let todayHeader = NSStackView(views: [todayKey, todaySpacer, todayVal])
        todayHeader.orientation = .horizontal; todayHeader.alignment = .centerY
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 5).isActive = true
        let metaSpacer = NSView(); metaSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let metaRow = NSStackView(views: [streakLbl, metaSpacer, bestLbl])
        metaRow.orientation = .horizontal; metaRow.alignment = .centerY
        let rhythmCap = microCap("rhythm · by hour")
        rhythm.translatesAutoresizingMaskIntoConstraints = false
        rhythm.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let activityCap = microCap("activity · 14 weeks")
        heat.translatesAutoresizingMaskIntoConstraints = false
        heat.heightAnchor.constraint(equalToConstant: 92).isActive = true
        setupBody(todayBody, [todayHeader, bar, metaRow, rhythmCap, rhythm, activityCap, heat])

        // ---- STATS body ----
        let recordsCap = microCap("personal bests")
        let r1 = recordRow("best 15s", recBest15)
        let r2 = recordRow("best 30s", recBest30)
        let r3 = recordRow("best 60s", recBest60)
        let r4 = recordRow("best 25 words", recBest25)
        style(summaryLbl, F.sans(10), Theme.faint)
        let recentCap = microCap("recent tests")
        spark.translatesAutoresizingMaskIntoConstraints = false
        spark.heightAnchor.constraint(equalToConstant: 38).isActive = true
        recentList.orientation = .vertical; recentList.alignment = .leading; recentList.spacing = 3
        recentList.translatesAutoresizingMaskIntoConstraints = false
        recentList.widthAnchor.constraint(equalToConstant: INNER).isActive = true
        setupBody(statsBody, [recordsCap, r1, r2, r3, r4, summaryLbl, recentCap, spark, recentList])

        // ---- FUN body ----
        let f1 = recordRow("novels written", novelsVal)
        let f2 = recordRow("pages", pagesVal)
        let f3 = recordRow("tweets", tweetsVal)
        let f4 = recordRow("finger travel", mileVal)
        let spreadCap = microCap("wpm spread")
        dist.translatesAutoresizingMaskIntoConstraints = false
        dist.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let weekCap = microCap("this week · words")
        week.translatesAutoresizingMaskIntoConstraints = false
        week.heightAnchor.constraint(equalToConstant: 40).isActive = true
        setupBody(funBody, [rankLbl, f1, f2, f3, f4, divider(), spreadCap, dist, weekCap, week])

        // body container
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.widthAnchor.constraint(equalToConstant: INNER).isActive = true
        bodyContainer.heightAnchor.constraint(equalToConstant: BODY_H).isActive = true
        nowBody.isHidden = false; todayBody.isHidden = true; statsBody.isHidden = true; funBody.isHidden = true

        // ---- footer ----
        style(allTimeLbl, F.sans(10.5), Theme.faint)
        let footSpacer = NSView(); footSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let quit = NSButton(); quit.isBordered = false; quit.bezelStyle = .regularSquare
        quit.attributedTitle = NSAttributedString(string: "quit", attributes: [
            .font: F.sans(10.5), .foregroundColor: Theme.faint])
        quit.target = self; quit.action = #selector(quitApp)
        let footer = NSStackView(views: [allTimeLbl, footSpacer, quit])
        footer.orientation = .horizontal; footer.alignment = .centerY

        // ---- root ----
        let root = NSStackView(views: [
            header, liveRow, miniRow, divider(),
            tabRow, bodyContainer, divider(),
            footer
        ])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        root.setCustomSpacing(16, after: liveRow)
        root.setCustomSpacing(10, after: tabRow)
        card.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            root.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            root.widthAnchor.constraint(equalToConstant: INNER),
        ])
        for v in [header, liveRow, miniRow, tabRow, testHeader, testTiles,
                  todayHeader, metaRow, footer,
                  test, sessionSpark, bar, rhythm, heat, spark, dist, week] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalToConstant: INNER).isActive = true
        }

        card.layoutSubtreeIfNeeded()
        window.setContentSize(card.fittingSize)
    }

    private func wireTest() {
        test.onProgress = { [weak self] in self?.updateTestLabels() }
        test.onFinish = { [weak self] r in
            guard let self = self else { return }
            self.engine.addTestResult(r)
            self.engine.setTestActive(false)
            self.updateTestLabels()
            self.refresh()
        }
        test.onRestart = { [weak self] in
            guard let self = self else { return }
            self.selectMode(self.selectedMode)
        }
    }

    // MARK: actions

    @objc private func toggleStart() { actions?.panelToggleSession(); refresh() }
    @objc private func showGear(_ sender: NSButton) { actions?.panelShowSettings(relativeTo: sender) }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func restartTest() { selectMode(selectedMode) }
    @objc private func pickChip(_ sender: Chip) {
        let m = modesForTags[sender.tag]; selectMode(m)
    }
    @objc private func pickTab(_ sender: NSButton) { selectTab(sender.tag) }

    private func selectTab(_ idx: Int) {
        currentTab = idx
        nowBody.isHidden = idx != 0
        todayBody.isHidden = idx != 1
        statsBody.isHidden = idx != 2
        funBody.isHidden = idx != 3
        let titles = ["now", "today", "stats", "fun"]
        for (i, b) in tabButtons.enumerated() {
            b.attributedTitle = TypeStyle.micro(titles[i], i == idx ? Theme.chrome : Theme.faint, size: 9.5, kern: 1.6)
        }
        if idx == 0 { window.makeFirstResponder(test) }
        else { abortTest(); window.makeFirstResponder(nil) }
        refresh()
    }

    private func selectMode(_ mode: TestMode) {
        if currentTab != 0 { selectTab(0) }
        selectedMode = mode
        for (i, c) in chips.enumerated() { c.set(modesForTags[i].label, selected: modesForTags[i] == mode) }
        engine.setTestActive(true)
        test.configure(mode: mode)
        window.makeFirstResponder(test)
        updateTestLabels()
    }
    private func abortTest() {
        if test.state == .ready || test.state == .running { engine.setTestActive(false) }
        for (i, c) in chips.enumerated() { c.set(modesForTags[i].label, selected: false) }
        test.abort(); updateTestLabels()
    }

    // MARK: show / hide

    func toggle(from button: NSStatusBarButton) {
        if window.isVisible { hide() } else { show(from: button) }
    }
    func show(from button: NSStatusBarButton) {
        refresh(); updateTestLabels()
        position(below: button)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if currentTab == 0 { window.makeFirstResponder(test) } else { window.makeFirstResponder(nil) }
        installMonitors()
        startRefreshTimer()
    }
    func hide() {
        removeMonitors(); stopRefreshTimer(); abortTest()
        window.orderOut(nil)
    }

    private func position(below button: NSStatusBarButton) {
        guard let bwin = button.window else { return }
        let inWin = button.convert(button.bounds, to: nil)
        let onScreen = bwin.convertToScreen(inWin)
        let size = window.frame.size
        let screen = bwin.screen ?? NSScreen.main
        let vis = screen?.visibleFrame ?? onScreen
        var x = onScreen.maxX - size.width
        x = max(vis.minX + 8, min(x, vis.maxX - size.width - 8))
        let y = onScreen.minY - size.height - 6
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installMonitors() {
        globalMon = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
        localMon = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            if e.keyCode == 53 { self?.hide(); return nil }   // Esc
            return e
        }
    }
    private func removeMonitors() {
        if let g = globalMon { NSEvent.removeMonitor(g); globalMon = nil }
        if let l = localMon { NSEvent.removeMonitor(l); localMon = nil }
    }
    private func startRefreshTimer() {
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common); refreshTimer = t
    }
    private func stopRefreshTimer() { refreshTimer?.invalidate(); refreshTimer = nil }

    // MARK: refresh

    func refresh() {
        let s = engine.snapshot()
        let active = s.isActive
        dot.on = active
        setPill(startBtn, active ? "stop" : "start")
        if active {
            bigWPM.stringValue = Fmt.wpm(s.liveWPM); setMicro(liveCap, "live wpm", Theme.muted)
        } else {
            bigWPM.stringValue = "\u{2014}"; setMicro(liveCap, "session off", Theme.faint)
        }
        avgVal.stringValue = s.hasMeaningfulAvg ? Fmt.wpm(s.avgWPM) : "\u{2014}"
        burstVal.stringValue = s.burstWPM > 0 ? Fmt.wpm(s.burstWPM) : "\u{2014}"
        wordsVal.stringValue = Fmt.int(Int(Double(s.characters)/5.0))
        timeVal.stringValue = Fmt.dur(s.activeSeconds)

        // rolling live-session graph
        if active {
            if !wasActive { liveSamples.removeAll(keepingCapacity: true) }
            liveSamples.append(max(0, s.liveWPM))
            if liveSamples.count > 48 { liveSamples.removeFirst(liveSamples.count - 48) }
        }
        wasActive = active
        sessionSpark.values = liveSamples

        // TODAY
        let liveWords = Int(Double(s.characters)/5.0)
        let goal = actions?.panelDailyGoal() ?? 1500
        let bonus = active ? liveWords : 0
        let todayTotal = engine.wordsToday() + bonus
        todayVal.stringValue = "\(Fmt.int(todayTotal)) / \(Fmt.int(goal))"
        bar.progress = goal > 0 ? Double(todayTotal)/Double(goal) : 0
        setMicro(streakLbl, "streak \(engine.streak(goal: goal, todayBonus: bonus))d", Theme.muted)
        setMicro(bestLbl, s.bestTestWPM > 0 ? "best \(Fmt.wpm(s.bestTestWPM))" : "best \u{2014}", Theme.muted, .right)
        rhythm.values = engine.hourly()

        // STATS
        heat.days = engine.dailySeries(days: 7 * 14)
        let bm = engine.bestByMode()
        func best(_ m: TestMode) -> String { let v = bm[m.label] ?? 0; return v > 0 ? Fmt.wpm(v) : "\u{2014}" }
        recBest15.stringValue = best(.time(15))
        recBest30.stringValue = best(.time(30))
        recBest60.stringValue = best(.time(60))
        recBest25.stringValue = best(.words(25))
        let accStr = engine.recentAccuracy(10).map { Fmt.pct($0) } ?? "\u{2014}"
        let burstStr = s.bestBurstWPM > 0 ? Fmt.wpm(s.bestBurstWPM) : "\u{2014}"
        let pbStr = s.bestTestWPM > 0 ? Fmt.wpm(s.bestTestWPM) : "\u{2014}"
        setMicro(summaryLbl, "burst \(burstStr)   ·   pb \(pbStr)   ·   acc \(accStr)", Theme.faint)
        spark.values = engine.recentTestWPMs(14)
        rebuildRecent()

        // FUN
        let funWords = Double(s.characters) / 5.0
        let keys = s.characters + s.backspaces
        setMicro(rankLbl, "rank · \(rankFor(s.avgWPM, s.hasMeaningfulAvg))", Theme.chrome)
        novelsVal.stringValue = pctStr(funWords / 80000.0 * 100.0)
        pagesVal.stringValue = String(format: "%.1f", funWords / 250.0)
        tweetsVal.stringValue = Fmt.int(s.characters / 280)
        mileVal.stringValue = String(format: "%.1f m", Double(keys) * 0.018)
        let wpms = engine.recentTestWPMs(40)
        if let lo = wpms.min(), let hi = wpms.max() {
            let bins = 11, span = max(1.0, hi - lo)
            var counts = Array(repeating: 0, count: bins)
            for w in wpms {
                var i = Int((w - lo) / span * Double(bins))
                if i >= bins { i = bins - 1 }; if i < 0 { i = 0 }
                counts[i] += 1
            }
            dist.values = counts
        } else { dist.values = [] }
        week.values = engine.dailySeries(days: 7).map { Int($0) }

        // footer
        setMicro(allTimeLbl,
                 "\(Fmt.compact(Int(Double(s.totalCharacters)/5.0))) words   ·   "
                 + "\(Fmt.int(s.totalSessions)) sessions   ·   \(Fmt.dur(s.totalActiveSeconds))",
                 Theme.faint)
    }

    private func rebuildRecent() {
        for v in recentList.arrangedSubviews { recentList.removeArrangedSubview(v); v.removeFromSuperview() }
        let tests = engine.recentTests(3)
        if tests.isEmpty {
            let l = NSTextField(labelWithAttributedString: TypeStyle.micro("no tests yet", Theme.faint, size: 9.5, kern: 1.2))
            l.lineBreakMode = .byClipping
            recentList.addArrangedSubview(l)
            return
        }
        for r in tests {
            let l = NSTextField(labelWithString: "\(r.mode)   ·   \(Fmt.wpm(r.wpm)) wpm   ·   \(Fmt.pct(r.accuracy))")
            l.font = F.mono(11, .regular); l.textColor = Theme.muted; l.lineBreakMode = .byClipping
            recentList.addArrangedSubview(l)
        }
    }

    private func updateTestLabels() {
        switch test.state {
        case .idle:
            testWPM.stringValue = "\u{2014}"; testAcc.stringValue = "\u{2014}"
            testTimer.stringValue = selectedMode.label
        default:
            let m = test.metrics()
            testWPM.stringValue = Fmt.wpm(m.wpm)
            testAcc.stringValue = Fmt.pct(m.acc)
            testTimer.stringValue = test.mode.isTime ? "\(Int(m.remaining.rounded()))s"
                                                      : "\(Int(m.elapsed.rounded()))s"
        }
    }
}
