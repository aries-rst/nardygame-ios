import Foundation

/// Daily-puzzle streak tracking — port of Android's Store.kt "daily" record
/// (dateNum = YYYYMMDD as an Int, same encoding the shared Mulberry32 puzzle
/// generator keys off of, so the puzzle matches Android for the same day).
enum NardyDaily {
    private static let key = "nardy.daily.v1"

    struct Record: Codable {
        var last: Int = 0
        var streak: Int = 0
    }

    static func todayNum() -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    static func yesterdayNum() -> Int {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let c = Calendar.current.dateComponents([.year, .month, .day], from: yesterday)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    static func fmtDate(_ n: Int) -> String {
        let s = String(n)
        guard s.count == 8 else { return s }
        let day = s.prefix(8).dropFirst(6)
        let month = s.dropFirst(4).prefix(2)
        let year = s.prefix(4)
        return "\(day).\(month).\(year)"
    }

    static func info() -> Record {
        guard let d = UserDefaults.standard.data(forKey: key),
              let r = try? JSONDecoder().decode(Record.self, from: d) else { return Record() }
        return r
    }

    /// Call once a puzzle is solved (not a replay) to extend/reset the streak.
    static func recordSolved(dateNum: Int) {
        var r = info()
        guard r.last != dateNum else { return }
        r.streak = (r.last == yesterdayNum()) ? r.streak + 1 : 1
        r.last = dateNum
        if let d = try? JSONEncoder().encode(r) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }
}
