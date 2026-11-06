import Foundation

/// UserDefaults-backed dice fairness & win/loss statistics, vs-bot only —
/// 1:1 port of Android's Store.kt dice/score tracking (recordRoll/recordResult).
final class NardyStats {
    static let shared = NardyStats()

    private let key = "nardy.stats.v1"

    struct Snapshot: Codable {
        var meFaces: [Int] = Array(repeating: 0, count: 6)
        var botFaces: [Int] = Array(repeating: 0, count: 6)
        var meRolls: Int = 0
        var botRolls: Int = 0
        var meDbl: Int = 0
        var botDbl: Int = 0
        // score[variantId][level] = [wins, losses]
        var score: [String: [String: [Int]]] = [:]
    }

    private var data: Snapshot

    private init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: d) {
            data = decoded
        } else {
            data = Snapshot()
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }

    func recordRoll(isBot: Bool, _ a: Int, _ b: Int) {
        if isBot {
            data.botFaces[a - 1] += 1
            data.botFaces[b - 1] += 1
            data.botRolls += 1
            if a == b { data.botDbl += 1 }
        } else {
            data.meFaces[a - 1] += 1
            data.meFaces[b - 1] += 1
            data.meRolls += 1
            if a == b { data.meDbl += 1 }
        }
        save()
    }

    func recordResult(variant: NVariant, level: Int, won: Bool) {
        var v = data.score[variant.rawValue] ?? [:]
        var r = v[String(level)] ?? [0, 0]
        r[won ? 0 : 1] += 1
        v[String(level)] = r
        data.score[variant.rawValue] = v
        save()
    }

    func result(variant: NVariant, level: Int) -> (wins: Int, losses: Int) {
        let r = data.score[variant.rawValue]?[String(level)] ?? [0, 0]
        return (r[0], r.count > 1 ? r[1] : 0)
    }

    func snapshot() -> Snapshot { data }

    func reset() {
        data = Snapshot()
        save()
    }
}
