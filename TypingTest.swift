import AppKit

enum TestMode: Equatable {
    case time(Int)
    case words(Int)
    var label: String {
        switch self { case .time(let s): return "\(s)s"; case .words(let n): return "\(n)w" }
    }
    var isTime: Bool { if case .time = self { return true }; return false }
}

enum TypingTest {
    static let wordList: [String] = [
        "the","of","to","and","a","in","is","it","you","that","he","was","for","on","are","with",
        "as","his","they","be","at","one","have","this","from","or","had","by","but","not","what",
        "all","were","when","we","there","can","an","your","which","their","said","if","do","will",
        "each","about","how","up","out","them","then","she","many","some","so","these","would","into",
        "has","more","her","two","like","him","see","time","could","no","make","than","first","been",
        "its","who","now","people","my","made","over","did","down","only","way","find","use","may",
        "water","long","little","very","after","words","called","just","where","most","know","get",
        "through","back","much","good","new","write","our","me","man","too","any","day","same","right",
        "look","think","also","around","another","came","come","work","three","must","because","does",
        "part","even","place","well","such","here","take","why","help","line","still","every","need",
        "house","picture","try","again","change","play","spell","air","away","animal","point","page",
        "letter","mother","answer","found","study","learn","should","world","high","near","add","food",
        "between","own","below","country","plant","last","school","father","keep","tree","never","start"
    ]
    static func words(_ n: Int) -> [String] { (0..<max(1, n)).map { _ in wordList.randomElement()! } }
}

final class TypingTestView: NSView {
    enum TState { case idle, ready, running, finished }

    private(set) var mode: TestMode = .time(30)
    private(set) var state: TState = .idle
    private var promptWords: [String] = []
    private var prompt: [Character] = []
    private var typed: [Character] = []
    private var startTime: Date?
    private var modeSeconds: Double = 30
    private var timer: Timer?

    var onStart: (() -> Void)?
    var onProgress: (() -> Void)?
    var onFinish: ((TestResult) -> Void)?
    var onRestart: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    deinit { timer?.invalidate() }

    // MARK: control

    func configure(mode: TestMode) {
        self.mode = mode
        switch mode {
        case .time(let s): modeSeconds = Double(s); promptWords = TypingTest.words(max(80, s * 5))
        case .words(let n): modeSeconds = 0; promptWords = TypingTest.words(n)
        }
        prompt = Array(promptWords.joined(separator: " "))
        typed = []; startTime = nil; state = .ready
        timer?.invalidate(); timer = nil
        needsDisplay = true
    }

    func abort() {
        state = .idle; typed = []; startTime = nil
        timer?.invalidate(); timer = nil
        needsDisplay = true
    }

    private func beginRunning() {
        startTime = Date(); state = .running
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common); timer = t
        onStart?()
    }

    private func tick() {
        guard state == .running else { return }
        if mode.isTime, elapsed() >= modeSeconds { finish() } else { onProgress?(); needsDisplay = true }
    }

    private func finish() {
        guard state == .running else { return }
        state = .finished
        timer?.invalidate(); timer = nil
        let m = metrics()
        let r = TestResult(date: Date(), mode: mode.label, wpm: m.wpm, raw: m.raw,
                           accuracy: m.acc, chars: correctCount(), seconds: m.elapsed)
        onFinish?(r)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch state {
        case .idle:
            return
        case .finished:
            if event.keyCode == 36 {            // return → retry
                if let r = onRestart { r() } else { configure(mode: mode); window?.makeFirstResponder(self) }
            }
            return
        case .ready, .running:
            let mods = event.modifierFlags
            if mods.contains(.command) || mods.contains(.control) { return }
            if state == .ready { beginRunning() }
            if event.keyCode == 51 {            // backspace
                if !typed.isEmpty { typed.removeLast() }
            } else if let ch = event.characters?.first, isTypable(ch) {
                if typed.count < prompt.count { typed.append(ch) }
            }
            if case .words = mode, typed.count >= prompt.count, !prompt.isEmpty { finish() }
            onProgress?(); needsDisplay = true
        }
    }

    private func isTypable(_ c: Character) -> Bool {
        guard let s = c.unicodeScalars.first else { return false }
        return s.value >= 0x20 && s.value != 0x7F
    }

    // MARK: metrics

    private func elapsed() -> Double { startTime.map { Date().timeIntervalSince($0) } ?? 0 }
    private func correctCount() -> Int {
        var c = 0; let n = min(typed.count, prompt.count)
        var i = 0; while i < n { if typed[i] == prompt[i] { c += 1 }; i += 1 }
        return c
    }
    struct Metrics { var wpm: Double; var raw: Double; var acc: Double; var remaining: Double; var elapsed: Double }
    func metrics() -> Metrics {
        let e = elapsed(); let correct = correctCount()
        let net = e > 0 ? (Double(correct)/5.0)/(e/60.0) : 0
        let raw = e > 0 ? (Double(typed.count)/5.0)/(e/60.0) : 0
        let acc = typed.isEmpty ? 100 : Double(correct)/Double(typed.count)*100
        let remaining = mode.isTime ? max(0, modeSeconds - e) : e
        return Metrics(wpm: net, raw: raw, acc: acc, remaining: remaining, elapsed: e)
    }

    // MARK: drawing

    private func layoutPrompt(cpl: Int) -> (line: [Int], col: [Int], total: Int) {
        var lineOf = [Int](repeating: 0, count: prompt.count)
        var colOf  = [Int](repeating: 0, count: prompt.count)
        var line = 0, col = 0, i = 0
        func newline() { line += 1; col = 0 }
        func place(_ count: Int) {
            var k = 0
            while k < count {
                lineOf[i] = line; colOf[i] = col; i += 1; col += 1; k += 1
                if col >= cpl { newline() }
            }
        }
        for (wi, w) in promptWords.enumerated() {
            let wlen = w.count
            if wi > 0 {
                if col + 1 + wlen > cpl {            // wrap before this word
                    lineOf[i] = line; colOf[i] = col; i += 1   // trailing space at line end
                    newline()
                } else {
                    lineOf[i] = line; colOf[i] = col; i += 1; col += 1   // inline space
                }
            }
            if col > 0 && col + wlen > cpl { newline() }
            place(wlen)
        }
        return (lineOf, colOf, max(1, line + 1))
    }

    override func draw(_ dirty: NSRect) {
        let pad: CGFloat = 10
        let font = F.mono(15, .regular)
        let cw = max(1, ("n" as NSString).size(withAttributes: [.font: font]).width)
        let lineH: CGFloat = 26
        let visible = 3

        if state == .idle || prompt.isEmpty {
            let s = "pick a mode below, then just start typing" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: F.sans(12), .foregroundColor: Theme.muted]
            let sz = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: (bounds.width - sz.width)/2, y: (bounds.height - sz.height)/2), withAttributes: attrs)
            return
        }

        let cpl = max(8, Int((bounds.width - 2*pad) / cw))
        let lay = layoutPrompt(cpl: cpl)
        let caretIndex = min(typed.count, prompt.count)
        let caretLine: Int
        let caretCol: Int
        if caretIndex < prompt.count {
            caretLine = lay.line[caretIndex]; caretCol = lay.col[caretIndex]
        } else if prompt.count > 0 {
            caretLine = lay.line[prompt.count - 1]; caretCol = lay.col[prompt.count - 1] + 1
        } else { caretLine = 0; caretCol = 0 }
        let firstVisible = max(0, min(caretLine - 1, max(0, lay.total - visible)))

        let dim = state == .finished
        for idx in 0..<prompt.count {
            let L = lay.line[idx]
            if L < firstVisible || L >= firstVisible + visible { continue }
            let row = L - firstVisible
            let x = pad + CGFloat(lay.col[idx]) * cw
            let y = pad + CGFloat(row) * lineH
            let color: NSColor
            if idx < typed.count {
                color = (typed[idx] == prompt[idx]) ? Theme.good : Theme.bad
            } else {
                color = Theme.faint
            }
            let c = String(prompt[idx]) as NSString
            c.draw(at: NSPoint(x: x, y: y),
                   withAttributes: [.font: font, .foregroundColor: dim ? color.withAlphaComponent(0.45) : color])
        }

        if state == .ready || state == .running,
           caretLine >= firstVisible, caretLine < firstVisible + visible {
            let row = caretLine - firstVisible
            let x = pad + CGFloat(caretCol) * cw
            let y = pad + CGFloat(row) * lineH
            let caret = NSBezierPath(rect: NSRect(x: x - 0.5, y: y + 3, width: 2, height: lineH - 9))
            Theme.chrome.setFill(); caret.fill()
        }

        if state == .finished {
            let s = "return to retry" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: F.sans(10.5), .foregroundColor: Theme.muted]
            let sz = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: bounds.width - pad - sz.width, y: bounds.height - sz.height - 4), withAttributes: attrs)
        }
    }
}
