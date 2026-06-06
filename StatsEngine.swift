import Foundation

struct StatsSnapshot {
    var isActive: Bool
    var sessionElapsed: Double
    var activeSeconds: Double
    var characters: Int
    var backspaces: Int
    var liveWPM: Double
    var avgWPM: Double
    var burstWPM: Double
    var hasMeaningfulAvg: Bool
    var totalCharacters: Int
    var totalActiveSeconds: Double
    var totalSessions: Int
    var bestSessionWPM: Double
    var bestBurstWPM: Double
    var bestTestWPM: Double
}

final class StatsEngine {
    static let charsPerWord = 5.0

    private let liveWindow = 5.0
    private let burstChars = 5
    private let historyWindow = 12.0
    var idleThreshold = 3.0

    private let lock = NSLock()
    private let store: SessionStore

    private var active = false
    private var testActive = false          // pause background counting during a test
    private var sessionStart: Date?
    private var lastKeystroke: Date?
    private var characters = 0
    private var backspaces = 0
    private var activeSeconds = 0.0
    private var sessionBurst = 0.0
    private var recent: [Date] = []
    private var allTime: AllTimeStats

    init(store: SessionStore) { self.store = store; self.allTime = store.load() }

    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }

    func setTestActive(_ v: Bool) { lock.lock(); testActive = v; lock.unlock() }

    func startSession() {
        lock.lock(); defer { lock.unlock() }
        active = true; sessionStart = Date(); lastKeystroke = nil
        characters = 0; backspaces = 0; activeSeconds = 0; sessionBurst = 0
        recent.removeAll(keepingCapacity: true)
    }

    func stopSession() {
        lock.lock()
        let was = active, chars = characters, bks = backspaces, act = activeSeconds, burst = sessionBurst
        let avg = avgLocked()
        active = false
        if was && chars > 0 {
            allTime.totalCharacters += chars
            allTime.totalBackspaces += bks
            allTime.totalActiveSeconds += act
            allTime.totalSessions += 1
            if burst > allTime.bestBurstWPM { allTime.bestBurstWPM = burst }
            if chars >= 50 && avg > allTime.bestSessionWPM { allTime.bestSessionWPM = avg }
            addWordsLocked(Int((Double(chars)/Self.charsPerWord).rounded()))
        }
        let snap = allTime
        lock.unlock()
        store.save(snap)
    }

    func resetSession() {
        lock.lock(); defer { lock.unlock() }
        sessionStart = active ? Date() : nil; lastKeystroke = nil
        characters = 0; backspaces = 0; activeSeconds = 0; sessionBurst = 0
        recent.removeAll(keepingCapacity: true)
    }

    func resetAllTime() {
        lock.lock(); allTime = AllTimeStats(); let s = allTime; lock.unlock(); store.save(s)
    }

    func persist() { lock.lock(); let s = allTime; lock.unlock(); store.save(s) }

    // MARK: intake

    func recordCharacter() {
        lock.lock(); defer { lock.unlock() }
        guard active, !testActive else { return }
        let now = Date()
        accumulateLocked(now)
        characters += 1
        let h = Calendar.current.component(.hour, from: now)
        if h >= 0 && h < allTime.hourlyChars.count { allTime.hourlyChars[h] += 1 }
        recent.append(now); trimLocked(now); burstLocked(now)
        lastKeystroke = now
    }
    func recordBackspace() {
        lock.lock(); defer { lock.unlock() }
        guard active, !testActive else { return }
        let now = Date(); accumulateLocked(now); backspaces += 1; lastKeystroke = now
    }

    private func accumulateLocked(_ now: Date) {
        if let last = lastKeystroke {
            let gap = now.timeIntervalSince(last)
            if gap > 0 { activeSeconds += min(gap, idleThreshold) }
        }
    }
    private func trimLocked(_ now: Date) {
        let cutoff = now.addingTimeInterval(-historyWindow)
        var i = 0; while i < recent.count && recent[i] < cutoff { i += 1 }
        if i > 0 { recent.removeFirst(i) }
    }
    private func burstLocked(_ now: Date) {
        guard recent.count >= burstChars else { return }
        let span = now.timeIntervalSince(recent[recent.count - burstChars])
        guard span > 0 else { return }
        let wpm = (Double(burstChars)/Self.charsPerWord)/(span/60.0)
        let capped = min(wpm, 400.0)
        if capped > sessionBurst { sessionBurst = capped }
    }
    private func liveLocked(_ now: Date) -> Double {
        let cutoff = now.addingTimeInterval(-liveWindow)
        var n = 0, i = recent.count - 1
        while i >= 0 && recent[i] >= cutoff { n += 1; i -= 1 }
        return (Double(n)/Self.charsPerWord)/(liveWindow/60.0)
    }
    private func avgLocked() -> Double {
        guard activeSeconds > 0 else { return 0 }
        return (Double(characters)/Self.charsPerWord)/(activeSeconds/60.0)
    }
    private func addWordsLocked(_ n: Int) {
        guard n > 0 else { return }
        let k = DayKey.key()
        allTime.dailyWords[k, default: 0] += n
    }

    // MARK: test results

    func addTestResult(_ r: TestResult) {
        lock.lock()
        allTime.tests.append(r)
        if allTime.tests.count > 60 { allTime.tests.removeFirst(allTime.tests.count - 60) }
        if r.wpm > allTime.bestTestWPM { allTime.bestTestWPM = r.wpm }
        addWordsLocked(Int((Double(r.chars)/Self.charsPerWord).rounded()))
        let s = allTime
        lock.unlock()
        store.save(s)
    }

    // MARK: reads for UI

    func snapshot() -> StatsSnapshot {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        return StatsSnapshot(
            isActive: active,
            sessionElapsed: sessionStart.map { now.timeIntervalSince($0) } ?? 0,
            activeSeconds: activeSeconds,
            characters: characters,
            backspaces: backspaces,
            liveWPM: active ? liveLocked(now) : 0,
            avgWPM: avgLocked(),
            burstWPM: sessionBurst,
            hasMeaningfulAvg: activeSeconds >= 2 && characters >= 5,
            totalCharacters: allTime.totalCharacters,
            totalActiveSeconds: allTime.totalActiveSeconds,
            totalSessions: allTime.totalSessions,
            bestSessionWPM: allTime.bestSessionWPM,
            bestBurstWPM: allTime.bestBurstWPM,
            bestTestWPM: allTime.bestTestWPM
        )
    }
    func wordsToday() -> Int { lock.lock(); defer { lock.unlock() }; return allTime.dailyWords[DayKey.key()] ?? 0 }
    func streak(goal: Int, todayBonus: Int) -> Int {
        lock.lock(); let d = allTime.dailyWords; lock.unlock()
        return currentStreak(daily: d, goal: goal, todayBonus: todayBonus)
    }
    func recentTestWPMs(_ n: Int) -> [Double] {
        lock.lock(); let t = allTime.tests; lock.unlock()
        return t.suffix(n).map { $0.wpm }
    }
    func recentTests(_ n: Int) -> [TestResult] {
        lock.lock(); let t = allTime.tests; lock.unlock()
        return Array(t.suffix(n).reversed())
    }
    func hourly() -> [Int] { lock.lock(); defer { lock.unlock() }; return allTime.hourlyChars }
    func dailySeries(days: Int) -> [Double] {
        lock.lock(); let d = allTime.dailyWords; lock.unlock()
        let cal = Calendar.current
        var out = [Double](); out.reserveCapacity(days)
        for i in stride(from: days - 1, through: 0, by: -1) {
            let day = cal.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            out.append(Double(d[DayKey.key(day)] ?? 0))
        }
        return out
    }
    func bestByMode() -> [String: Double] {
        lock.lock(); let t = allTime.tests; lock.unlock()
        var m = [String: Double]()
        for r in t { m[r.mode] = max(m[r.mode] ?? 0, r.wpm) }
        return m
    }
    func recentAccuracy(_ n: Int) -> Double? {
        lock.lock(); let t = allTime.tests; lock.unlock()
        let last = t.suffix(n); guard !last.isEmpty else { return nil }
        return last.map { $0.accuracy }.reduce(0, +) / Double(last.count)
    }
}
