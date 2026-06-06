import Foundation

struct TestResult: Codable {
    var date: Date
    var mode: String      // "15s", "30s", "25w"
    var wpm: Double        // net
    var raw: Double
    var accuracy: Double   // 0-100
    var chars: Int          // correctly typed characters
    var seconds: Double
}

struct AllTimeStats: Codable {
    var totalCharacters: Int
    var totalBackspaces: Int
    var totalActiveSeconds: Double
    var totalSessions: Int
    var bestSessionWPM: Double
    var bestBurstWPM: Double
    var bestTestWPM: Double
    var firstUsed: Date
    var dailyWords: [String: Int]
    var hourlyChars: [Int]
    var tests: [TestResult]

    init() {
        totalCharacters = 0; totalBackspaces = 0; totalActiveSeconds = 0; totalSessions = 0
        bestSessionWPM = 0; bestBurstWPM = 0; bestTestWPM = 0
        firstUsed = Date(); dailyWords = [:]; hourlyChars = Array(repeating: 0, count: 24); tests = []
    }

    enum CodingKeys: String, CodingKey {
        case totalCharacters, totalBackspaces, totalActiveSeconds, totalSessions
        case bestSessionWPM, bestBurstWPM, bestTestWPM, firstUsed, dailyWords, hourlyChars, tests
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        totalCharacters    = try c.decodeIfPresent(Int.self, forKey: .totalCharacters) ?? 0
        totalBackspaces    = try c.decodeIfPresent(Int.self, forKey: .totalBackspaces) ?? 0
        totalActiveSeconds = try c.decodeIfPresent(Double.self, forKey: .totalActiveSeconds) ?? 0
        totalSessions      = try c.decodeIfPresent(Int.self, forKey: .totalSessions) ?? 0
        bestSessionWPM     = try c.decodeIfPresent(Double.self, forKey: .bestSessionWPM) ?? 0
        bestBurstWPM       = try c.decodeIfPresent(Double.self, forKey: .bestBurstWPM) ?? 0
        bestTestWPM        = try c.decodeIfPresent(Double.self, forKey: .bestTestWPM) ?? 0
        firstUsed          = try c.decodeIfPresent(Date.self, forKey: .firstUsed) ?? Date()
        dailyWords         = try c.decodeIfPresent([String: Int].self, forKey: .dailyWords) ?? [:]
        var hc             = try c.decodeIfPresent([Int].self, forKey: .hourlyChars) ?? []
        if hc.count < 24 { hc += Array(repeating: 0, count: 24 - hc.count) }
        else if hc.count > 24 { hc = Array(hc.prefix(24)) }
        hourlyChars        = hc
        tests              = try c.decodeIfPresent([TestResult].self, forKey: .tests) ?? []
    }
}

enum DayKey {
    static let fmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static func key(_ d: Date = Date()) -> String { fmt.string(from: d) }
}

func currentStreak(daily: [String: Int], goal: Int, todayBonus: Int = 0) -> Int {
    guard goal > 0 else { return 0 }
    let cal = Calendar.current
    func words(_ d: Date) -> Int {
        let base = daily[DayKey.key(d)] ?? 0
        return cal.isDateInToday(d) ? base + todayBonus : base
    }
    var day = Date()
    if words(day) < goal {                       // today not met yet → don't break streak mid-day
        guard let y = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
        day = y
    }
    var streak = 0
    while words(day) >= goal {
        streak += 1
        guard let p = cal.date(byAdding: .day, value: -1, to: day) else { break }
        day = p
    }
    return streak
}

final class SessionStore {
    private let url: URL
    private let q = DispatchQueue(label: "mercury.store")

    init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Mercury", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("stats.json")
    }
    func load() -> AllTimeStats {
        guard let data = try? Data(contentsOf: url) else { return AllTimeStats() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(AllTimeStats.self, from: data)) ?? AllTimeStats()
    }
    func save(_ s: AllTimeStats) {
        q.async {
            let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? e.encode(s) { try? data.write(to: self.url, options: [.atomic]) }
        }
    }
}
