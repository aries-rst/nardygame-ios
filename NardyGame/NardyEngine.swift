import Foundation

// MARK: - Rules engine — 1:1 Swift port of the Android Kotlin Engine.kt.
// Five games on one board: long nardy, backgammon (short), tavla, plakoto, fevga.
// Positions are stored per player in that player's OWN path coordinates:
// index 0 = head/start, 23 = last point before home exit, 18...23 = home, 24 = borne off.

enum NVariant: String, CaseIterable, Codable {
    case long, short, tavla, plakoto, fevga
}

struct NCfg {
    let same: Bool
    let hit: Bool
    let pin: Bool
    let head: Bool
    let runner: Bool
    let prime: Bool
    let maxWin: Int
    let startHead: Bool
    let useOpening: Bool
    let prevWinner: Bool
    let cube: Bool
    var noHitRun: Bool = false
    var noWaste: Bool = false
    var mother: Bool = false
}

struct NMove: Equatable {
    var from: Int
    var to: Int
    var die: Int
    var p: Int
    var hit: Bool
    var pinned: Bool
}

/// Mutable game state — a reference type, mirroring Kotlin's `class GState`:
/// the rules engine relies on reference-vs-explicit-copy semantics throughout
/// (`copy()` is the only deep copy; every other access shares the instance).
final class NGState {
    let v: NVariant
    var pos: [[Int]]      // pos[player][ownPathIndex 0...23] checker counts
    var pin: [[Int]]      // Plakoto: 1 where an opponent checker sits pinned under mine
    var frozen: [Int]     // Tavla no-hit-run: points a checker can't leave again this turn
    var bar: [Int]
    var off: [Int]
    var turn: Int
    var dice: [Int]
    var left: [Int]
    var headUsed: Int
    var turnsTaken: [Int]
    var puzzle: Bool
    var lastMove: NMove?
    var mother: Int
    var cube: Int
    var cubeOwner: Int

    init(v: NVariant, pos: [[Int]], pin: [[Int]], frozen: [Int], bar: [Int], off: [Int], turn: Int,
         dice: [Int], left: [Int], headUsed: Int, turnsTaken: [Int], puzzle: Bool, lastMove: NMove?,
         mother: Int, cube: Int, cubeOwner: Int) {
        self.v = v; self.pos = pos; self.pin = pin; self.frozen = frozen; self.bar = bar; self.off = off
        self.turn = turn; self.dice = dice; self.left = left; self.headUsed = headUsed
        self.turnsTaken = turnsTaken; self.puzzle = puzzle; self.lastMove = lastMove
        self.mother = mother; self.cube = cube; self.cubeOwner = cubeOwner
    }

    func copy() -> NGState {
        NGState(v: v, pos: [pos[0], pos[1]], pin: [pin[0], pin[1]], frozen: frozen, bar: bar, off: off,
                 turn: turn, dice: dice, left: left, headUsed: headUsed, turnsTaken: turnsTaken,
                 puzzle: puzzle, lastMove: lastMove, mother: mother, cube: cube, cubeOwner: cubeOwner)
    }
}

struct NStep {
    var from: Int
    var die: Int
    var to: Int
    var state: NGState
}

struct NFinal {
    var seq: [NStep]
    var state: NGState
}

final class NPuzzle {
    let start: NGState
    let dice: [[Int]]
    let turns: Int
    let tricky: Bool
    init(start: NGState, dice: [[Int]], turns: Int, tricky: Bool) {
        self.start = start; self.dice = dice; self.turns = turns; self.tricky = tricky
    }
}

/// Reference-type memo box — Kotlin's `HashMap` is shared by reference across
/// the whole recursive search; a Swift `Dictionary` is a value type, so the
/// memo needs this thin class wrapper to get the same sharing behavior.
final class NMemo {
    var m: [String: Int] = [:]
}

enum NEngine {
    static let CFG: [NVariant: NCfg] = [
        .long: NCfg(same: true, hit: false, pin: false, head: true, runner: false, prime: true, maxWin: 2, startHead: true, useOpening: false, prevWinner: false, cube: false),
        .fevga: NCfg(same: true, hit: false, pin: false, head: false, runner: true, prime: true, maxWin: 2, startHead: true, useOpening: false, prevWinner: true, cube: false),
        .short: NCfg(same: false, hit: true, pin: false, head: false, runner: false, prime: false, maxWin: 3, startHead: false, useOpening: true, prevWinner: false, cube: true),
        .tavla: NCfg(same: false, hit: true, pin: false, head: false, runner: false, prime: false, maxWin: 2, startHead: false, useOpening: false, prevWinner: true, cube: false, noHitRun: true, noWaste: true),
        .plakoto: NCfg(same: false, hit: false, pin: true, head: false, runner: false, prime: false, maxWin: 2, startHead: true, useOpening: false, prevWinner: true, cube: false, mother: true),
    ]
    static let VARIANTS: [NVariant] = [.long, .short, .tavla, .plakoto, .fevga]
    static func cfg(_ v: NVariant) -> NCfg { CFG[v]! }

    /// Unbiased die from the system's cryptographic generator.
    static func fairDie() -> Int { Int.random(in: 1...6) }

    static func boardOf(_ v: NVariant, _ p: Int, _ i: Int) -> Int {
        if p == 0 { return i }
        return cfg(v).same ? (i + 12) % 24 : 23 - i
    }
    static func pathOf(_ v: NVariant, _ p: Int, _ b: Int) -> Int {
        if p == 0 { return b }
        return cfg(v).same ? (b + 12) % 24 : 23 - b
    }

    static func newGame(_ v: NVariant) -> NGState {
        let s = NGState(
            v: v,
            pos: [[Int](repeating: 0, count: 24), [Int](repeating: 0, count: 24)],
            pin: [[Int](repeating: 0, count: 24), [Int](repeating: 0, count: 24)],
            frozen: [Int](repeating: 0, count: 24), bar: [0, 0], off: [0, 0], turn: 0,
            dice: [], left: [], headUsed: 0, turnsTaken: [0, 0], puzzle: false, lastMove: nil,
            mother: -1, cube: 1, cubeOwner: -1
        )
        if cfg(v).startHead {
            s.pos[0][0] = 15; s.pos[1][0] = 15
        } else {
            for p in 0...1 {
                s.pos[p][0] = 2; s.pos[p][11] = 5; s.pos[p][16] = 3; s.pos[p][18] = 5
            }
        }
        return s
    }

    @discardableResult
    static func setDice(_ s: NGState, _ a: Int, _ b: Int) -> NGState {
        s.dice = [a, b]
        s.left = a == b ? [a, a, a, a] : [a, b]
        s.headUsed = 0
        s.frozen = [Int](repeating: 0, count: 24)
        return s
    }

    private static func headLimit(_ s: NGState) -> Int {
        if !cfg(s.v).head { return 99 }
        let p = s.turn
        if s.turnsTaken[p] == 0 && s.dice.count == 2 && s.dice[0] == s.dice[1] &&
            (s.dice[0] == 6 || s.dice[0] == 4 || s.dice[0] == 3) { return 2 }
        return 1
    }

    static func allHome(_ s: NGState, _ p: Int) -> Bool {
        if s.bar[p] > 0 { return false }
        var c = s.off[p]
        for i in 18..<24 { c += s.pos[p][i] }
        return c == 15
    }

    /// Fevga: until the first checker has passed the opponent's start, no other checker may move.
    private static func runnerPhase(_ s: NGState, _ p: Int) -> Bool {
        if s.off[p] > 0 { return false }
        for i in 13..<24 { if s.pos[p][i] > 0 { return false } }
        return true
    }

    /// Long nardy / Fevga: 6 consecutive points are illegal unless an opponent checker is ahead of them.
    private static func violatesPrime(_ n: NGState, _ p: Int) -> Bool {
        let o = 1 - p; let v = n.v
        for b in 0..<24 {
            var ok = true
            for k in 0..<6 {
                if n.pos[p][pathOf(v, p, (b + k) % 24)] == 0 { ok = false; break }
            }
            if !ok { continue }
            let s0 = pathOf(v, o, b)
            if s0 + 5 > 23 { continue }
            var ahead = false
            for i in (s0 + 6)..<24 { if n.pos[o][i] > 0 { ahead = true; break } }
            if !ahead { return true }
        }
        return false
    }

    static func movable(_ s: NGState, _ p: Int, _ i: Int) -> Int {
        s.pos[p][i] - s.pin[p][i] - (p == s.turn ? s.frozen[i] : 0)
    }

    /// Apply one checker move with one die; returns the new state or nil if illegal.
    static func tryMove(_ s: NGState, _ from: Int, _ die: Int) -> NGState? {
        let p = s.turn; let o = 1 - p; let v = s.v; let c = cfg(v)
        if s.mother >= 0 { return nil }
        if !s.left.contains(die) { return nil }
        if c.hit && s.bar[p] > 0 && from != -1 { return nil }
        if from == -1 {
            if !c.hit || s.bar[p] == 0 { return nil }
        } else if from < 0 || from > 23 || movable(s, p, from) <= 0 { return nil }
        if c.head && from == 0 && s.headUsed >= headLimit(s) { return nil }
        if c.runner && !s.puzzle && runnerPhase(s, p) {
            let out = 15 - s.pos[p][0]
            if out == 0 { if from != 0 { return nil } } else { if from == 0 { return nil } }
        }
        var to = from == -1 ? die - 1 : from + die
        let n = s.copy()
        var hit = false
        var pinned = false
        if to >= 24 {
            if !allHome(s, p) { return nil }
            if to > 24 && from > 18 {
                for i in 18..<from { if s.pos[p][i] > 0 { return nil } }
            }
            n.pos[p][from] -= 1; n.off[p] += 1; to = 24
        } else {
            if c.noWaste && allHome(s, p) {
                for i in 18..<24 {
                    if movable(s, p, i) > 0 && i + die >= 24 {
                        let exact = (i + die == 24)
                        var noneFurtherBack = true
                        if i > 18 {
                            for k in 18..<i { if s.pos[p][k] > 0 { noneFurtherBack = false; break } }
                        }
                        if exact || noneFurtherBack { return nil }
                    }
                }
            }
            if !s.puzzle {
                let b = boardOf(v, p, to); let oi = pathOf(v, o, b)
                let oc = s.pos[o][oi]; let ou = oc - s.pin[o][oi]
                if c.hit {
                    if oc >= 2 { return nil }
                    if oc == 1 { n.pos[o][oi] = 0; n.bar[o] += 1; hit = true }
                } else if c.pin {
                    if ou >= 2 { return nil }
                    if ou == 1 {
                        if s.pos[p][to] > 0 { return nil } // my checker is already there
                        n.pin[o][oi] = 1; pinned = true
                    }
                } else if oc > 0 { return nil }
            }
            if from == -1 { n.bar[p] -= 1 } else { n.pos[p][from] -= 1 }
            n.pos[p][to] += 1
            if c.noHitRun && hit && to >= 18 { n.frozen[to] += 1 }
        }
        // Plakoto: leaving a point releases a checker pinned under it.
        if c.pin && from >= 0 && n.pos[p][from] - n.pin[p][from] == 0 {
            n.pin[o][pathOf(v, o, boardOf(v, p, from))] = 0
        }
        if c.head && from == 0 { n.headUsed += 1 }
        if let idx = n.left.firstIndex(of: die) { n.left.remove(at: idx) }
        if c.prime && !s.puzzle && violatesPrime(n, p) { return nil }
        // Plakoto: pinning the opponent's mother wins double, unless I still hold my own start point.
        if c.mother && pinned && pathOf(v, o, boardOf(v, p, to)) == 0 && n.pos[p][0] == 0 { n.mother = p }
        n.lastMove = NMove(from: from, to: to, die: die, p: p, hit: hit, pinned: pinned)
        return n
    }

    static func key(_ s: NGState) -> String {
        var sb = ""
        for x in s.pos[0] { sb += "\(x)," }
        sb += "|"
        for x in s.pos[1] { sb += "\(x)," }
        sb += "|"
        for x in s.pin[0] { sb += "\(x)" }
        for x in s.pin[1] { sb += "\(x)" }
        sb += "|"
        for x in s.frozen { sb += "\(x)" }
        sb += "|\(s.bar[0]),\(s.bar[1])|\(s.off[0]),\(s.off[1])|"
        for x in s.left.sorted() { sb += "\(x)" }
        sb += "|\(s.headUsed)|\(s.mother)"
        return sb
    }

    private static func stepsFrom(_ s: NGState) -> [NStep] {
        var res: [NStep] = []
        let p = s.turn
        var seenDice = Set<Int>()
        var dice: [Int] = []
        for d in s.left where seenDice.insert(d).inserted { dice.append(d) }
        var froms: [Int] = []
        if cfg(s.v).hit && s.bar[p] > 0 { froms.append(-1) }
        else { for i in 0..<24 where s.pos[p][i] > 0 { froms.append(i) } }
        for d in dice {
            for f in froms {
                if let n = tryMove(s, f, d) {
                    res.append(NStep(from: f, die: d, to: n.lastMove!.to, state: n))
                }
            }
        }
        return res
    }

    private static func maxDepth(_ s: NGState, _ memo: NMemo) -> Int {
        if s.left.isEmpty || s.mother >= 0 || s.off[s.turn] == 15 { return 0 }
        let k = key(s)
        if let v = memo.m[k] { return v }
        var best = 0
        for st in stepsFrom(s) {
            let d = 1 + maxDepth(st.state, memo)
            if d > best { best = d }
            if best == s.left.count { break }
        }
        memo.m[k] = best
        return best
    }

    /// A winning step ends the turn at once.
    private static func finished(_ st: NGState) -> Bool { st.mother >= 0 || st.off[st.turn] == 15 }

    /// Legal single steps: part of a sequence using the most dice; if only one
    /// of two dice can be played, the larger one.
    static func legalSteps(_ s: NGState, _ memo: NMemo = NMemo()) -> [NStep] {
        if finished(s) { return [] }
        let steps = stepsFrom(s)
        if steps.isEmpty { return [] }
        let target = maxDepth(s, memo)
        var ok = steps.filter { finished($0.state) || 1 + maxDepth($0.state, memo) == target }
        if target == 1 && s.left.count == 2 && s.left[0] != s.left[1] {
            let hi = max(s.left[0], s.left[1])
            if ok.contains(where: { $0.die == hi }) { ok = ok.filter { $0.die == hi } }
        }
        return ok
    }

    /// All distinct end-of-turn positions reachable with legal play.
    static func allFinals(_ s: NGState) -> [NFinal] {
        var out: [NFinal] = []
        var seen = Set<String>()
        var nodes = Set<String>()
        let memo = NMemo()

        func rec(_ st: NGState, _ seq: inout [NStep], _ first: Bool) {
            let list: [NStep] = first ? legalSteps(st, memo) : (finished(st) ? [] : stepsFrom(st))
            let need = first ? -1 : maxDepth(st, memo)
            if list.isEmpty || (!first && need == 0) {
                let k = key(st)
                if !seen.contains(k) { seen.insert(k); out.append(NFinal(seq: seq, state: st)) }
                return
            }
            let k2 = key(st)
            if nodes.contains(k2) { return }
            nodes.insert(k2)
            for x in list {
                if !first && !finished(x.state) && 1 + maxDepth(x.state, memo) < need { continue }
                seq.append(x)
                rec(x.state, &seq, false)
                seq.removeLast()
            }
        }
        var seq: [NStep] = []
        rec(s, &seq, true)
        if out.isEmpty { out.append(NFinal(seq: [], state: s)) }
        return out
    }

    static func endTurn(_ s: NGState) -> NGState {
        let n = s.copy()
        n.turnsTaken[s.turn] += 1
        if !s.puzzle { n.turn = 1 - s.turn }
        n.dice = []; n.left = []; n.headUsed = 0; n.frozen = [Int](repeating: 0, count: 24)
        return n
    }

    static func winner(_ s: NGState) -> Int {
        if s.mother >= 0 { return s.mother }
        if s.off[0] == 15 { return 0 }
        if !s.puzzle && s.off[1] == 15 { return 1 }
        return -1
    }

    /// 1 = single, 2 = mars/gammon (or mother pin), 3 = backgammon (short only). Not multiplied by the cube.
    static func winScore(_ s: NGState, _ w: Int) -> Int {
        let l = 1 - w
        if s.mother >= 0 { return 2 }
        if s.off[l] > 0 { return 1 }
        if cfg(s.v).maxWin == 2 { return 2 }
        if s.bar[l] > 0 { return 3 }
        for i in 0..<6 { if s.pos[l][i] > 0 { return 3 } }
        return 2
    }

    static func pip(_ s: NGState, _ p: Int) -> Int {
        var t = s.bar[p] * 25
        for i in 0..<24 { t += s.pos[p][i] * (24 - i) }
        return t
    }

    private static func exposure(_ s: NGState, _ p: Int, _ i: Int) -> Double {
        let o = 1 - p; let v = s.v; let b = boardOf(v, p, i); let ob = pathOf(v, o, b)
        var prob = 0.0
        if s.bar[o] > 0 && ob < 6 { prob += 0.31 }
        for j in 0..<ob {
            if s.pos[o][j] - s.pin[o][j] <= 0 { continue }
            let d = ob - j
            if d <= 6 { prob += 0.31 } else if d <= 12 { prob += 0.08 }
        }
        return min(prob, 0.95)
    }

    static func evaluate(_ s: NGState, _ p: Int) -> Double {
        let o = 1 - p; let v = s.v; let c = cfg(v)
        if s.mother == p { return 150000.0 }
        if s.mother == o { return -100000.0 }
        if s.off[p] == 15 { return 100000.0 + (s.off[o] == 0 ? 50000.0 : 0.0) }
        if !s.puzzle && s.off[o] == 15 { return -100000.0 }
        var e = Double(pip(s, o) - pip(s, p))
        if c.same {
            var cum = [Int](repeating: 0, count: 25)
            for i in 0..<24 { cum[i + 1] = cum[i] + s.pos[o][i] }
            var run = 0; var start = 0
            for oi in 0...24 {
                let owned = oi < 24 && s.pos[p][pathOf(v, p, boardOf(v, o, oi))] > 0
                if owned {
                    if run == 0 { start = oi }
                    run += 1
                } else {
                    if run >= 2 && cum[start] > 0 {
                        let r = min(run, 6)
                        e += Double(r * r) * 0.7
                    }
                    run = 0
                }
            }
            for i in 1..<24 { if s.pos[p][i] > 3 { e -= Double(s.pos[p][i] - 3) * 0.5 } }
            var spread = 0
            for i in 1..<18 { if s.pos[p][i] > 0 { spread += 1 } }
            e += Double(spread) * 0.4
            e -= Double(max(0, s.pos[p][0] - 10)) * 0.5 * Double(min(s.turnsTaken[p], 8))
        } else if c.hit {
            for i in 0..<24 {
                let cnt = s.pos[p][i]
                if cnt >= 2 { e += i >= 18 ? 3.0 : (i >= 12 ? 1.5 : 0.5) }
                if cnt == 1 { e -= exposure(s, p, i) * Double(i + 6) }
            }
            e += Double(s.bar[o] * 6)
            e -= Double(s.bar[p] * 6)
        } else if c.pin {
            for i in 0..<24 {
                let cnt = s.pos[p][i]
                let oi = pathOf(v, o, boardOf(v, p, i))
                if s.pin[o][oi] != 0 { e += 14.0 + Double(23 - oi) * 0.6 }
                if s.pin[p][i] != 0 { e -= 14.0 + Double(23 - i) * 0.6 }
                if cnt >= 2 { e += i >= 18 ? 2.5 : 1.0 }
                if cnt == 1 && s.pin[p][i] == 0 { e -= exposure(s, p, i) * Double(i + 8) * 0.8 }
            }
            if s.pos[p][0] == 1 { e -= 10 }
        }
        return e
    }

    /// level: 0 easy, 1 medium, 2 hard.
    static func aiChoose(_ s: NGState, _ level: Int) -> [NStep] {
        let p = s.turn
        let finals = allFinals(s)
        if finals.count == 1 { return finals[0].seq }
        let scored = finals.map { ($0, evaluate($0.state, p)) }.sorted { $0.1 > $1.1 }
        if level == 0 {
            if Double.random(in: 0..<1) < 0.45 {
                let idx = Int(Double(scored.count) * Double.random(in: 0..<1))
                return scored[idx].0.seq
            }
            let idx = min(scored.count - 1, Int(4 * Double.random(in: 0..<1)))
            return scored[idx].0.seq
        }
        if level == 1 || scored[0].1 >= 100000 { return scored[0].0.seq }
        // hard: 1-ply lookahead over all 21 opponent rolls
        var best = scored[0]; var bestV = -Double.infinity
        for cand in scored.prefix(6) {
            let base = endTurn(cand.0.state)
            var sum = 0.0; var w = 0
            for a in 1...6 {
                for b in a...6 {
                    let wt = a == b ? 1 : 2
                    let t = setDice(base.copy(), a, b)
                    var worst = Double.infinity
                    for r in allFinals(t) {
                        let x = evaluate(r.state, p)
                        if x < worst { worst = x }
                    }
                    sum += Double(wt) * worst
                    w += wt
                }
            }
            let value = sum / Double(w)
            if value > bestV { bestV = value; best = cand }
        }
        return best.0.seq
    }

    // MARK: - Doubling cube

    static func winProb(_ s: NGState, _ p: Int) -> Double {
        let e = evaluate(s, p) + (s.turn == p ? 4.0 : -4.0)
        if e >= 100000 { return 1.0 }
        if e <= -100000 { return 0.0 }
        return 1.0 / (1.0 + exp(-e / 14.0))
    }
    static func canOffer(_ s: NGState, _ p: Int, _ crawford: Bool) -> Bool {
        cfg(s.v).cube && !crawford && s.cube < 64 && (s.cubeOwner == -1 || s.cubeOwner == p) && s.dice.isEmpty
    }
    static func botShouldDouble(_ s: NGState, _ p: Int) -> Bool { winProb(s, p) > 0.70 }
    static func botShouldTake(_ s: NGState, _ p: Int) -> Bool { winProb(s, p) >= 0.25 }

    // MARK: - Daily puzzle (long nardy bear-off race, dice known ahead)

    /// Same generator as the Android/HTML prototype so every platform gets the same daily puzzle.
    final class NMulberry32 {
        private var a: UInt32
        init(seed: Int32) { a = UInt32(bitPattern: seed) }
        func next() -> Double {
            a = a &+ 0x6D2B79F5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ (t ^ (t >> 7)) &* (61 | t)) ^ t
            return Double(t ^ (t >> 14)) / 4294967296.0
        }
    }

    private static func puzzleState(_ dice: [[Int]], _ t: Int, _ base: NGState) -> NGState {
        let x = base.copy()
        x.turn = 0
        return setDice(x, dice[t][0], dice[t][1])
    }

    private static func minTurns(_ start: NGState, _ dice: [[Int]], _ maxT: Int) -> Int {
        var frontier = [start]
        for t in 0..<maxT {
            var next: [String: NGState] = [:]
            for st in frontier {
                for f in allFinals(puzzleState(dice, t, st)) {
                    if f.state.off[0] == 15 { return t + 1 }
                    let e = endTurn(f.state)
                    let k = key(e)
                    if next[k] == nil { next[k] = e }
                }
                if next.count > 30000 { break }
            }
            frontier = Array(next.values)
        }
        return Int.max
    }

    private static func greedyTurns(_ start: NGState, _ dice: [[Int]], _ maxT: Int) -> Int {
        var st = start
        for t in 0..<maxT {
            var best: NGState? = nil
            var bv = -Double.infinity
            for f in allFinals(puzzleState(dice, t, st)) {
                let value = Double(f.state.off[0]) * 100.0 - Double(pip(f.state, 0))
                if value > bv { bv = value; best = f.state }
            }
            guard let b = best else { break }
            if b.off[0] == 15 { return t + 1 }
            st = endTurn(b)
        }
        return Int.max
    }

    static func canSolve(_ st: NGState, _ dice: [[Int]], _ t: Int, _ turns: Int) -> Bool {
        if st.off[0] == 15 { return true }
        if t >= turns { return false }
        for f in allFinals(puzzleState(dice, t, st)) {
            if f.state.off[0] == 15 { return true }
            if canSolve(endTurn(f.state), dice, t + 1, turns) { return true }
        }
        return false
    }

    /// Hint: first step of a winning line from the current mid-turn state, or nil if no longer solvable.
    static func puzzleHint(_ cur: NGState, _ dice: [[Int]], _ t: Int, _ turns: Int) -> NStep? {
        for f in allFinals(cur) {
            if f.state.off[0] == 15 || canSolve(endTurn(f.state), dice, t + 1, turns) { return f.seq.first }
        }
        return nil
    }

    static func makePuzzle(_ dateNum: Int) -> NPuzzle? {
        var fallback: NPuzzle? = nil
        for attempt in 0..<80 {
            let seedLong = Int64(dateNum) * 97 + Int64(attempt) * 7919 + 13
            let r = NMulberry32(seed: Int32(truncatingIfNeeded: seedLong))
            let s = newGame(.long)
            s.pos[0] = [Int](repeating: 0, count: 24)
            s.pos[1] = [Int](repeating: 0, count: 24)
            s.puzzle = true
            let count = 5 + Int(floor(r.next() * 5))
            let outside = 1 + Int(floor(r.next() * 3))
            for i in 0..<count {
                let idx = i < outside ? 10 + Int(floor(r.next() * 8)) : 18 + Int(floor(r.next() * 6))
                s.pos[0][idx] += 1
            }
            s.off[0] = 15 - count
            s.turnsTaken[0] = 6; s.turnsTaken[1] = 6
            var dice: [[Int]] = []
            for _ in 0..<8 {
                dice.append([1 + Int(floor(r.next() * 6)), 1 + Int(floor(r.next() * 6))])
            }
            let turns = minTurns(s, dice, 6)
            if turns < 2 || turns > 5 { continue }
            let g = greedyTurns(s, dice, 8)
            let pz = NPuzzle(start: s, dice: Array(dice.prefix(turns)), turns: turns, tricky: g > turns)
            if g > turns { return pz }
            if fallback == nil { fallback = pz }
        }
        return fallback
    }
}
