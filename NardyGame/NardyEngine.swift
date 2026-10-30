import Foundation

enum NardyColor: String, Codable, Equatable {
    case white
    case black
}

/// Длинные нарды (Long Nardy) — simplified engine: both players move in the same
/// rotational direction from their own head point (relative index 0) around a
/// 24-point track to their own home board (relative indices 18...23) and bear off.
/// This variant has no hitting/blocking: any number of checkers of either color may
/// share a physical point.
final class NardyEngine: ObservableObject {
    static let pointsPerSide = 24
    static let checkersPerPlayer = 15
    static let homeStart = 18 // relative index where a player's home board begins

    @Published var points: [NardyColor: [Int]] = [:] // relative index 0...23 -> checker count
    @Published var borneOff: [NardyColor: Int] = [.white: 0, .black: 0]
    @Published var turn: NardyColor = .white
    @Published var dice: [Int] = []
    @Published var lastRoll: [Int] = []
    @Published var winner: NardyColor? = nil
    @Published var selectedPoint: Int? = nil

    init() {
        reset()
    }

    func reset() {
        var white = [Int](repeating: 0, count: Self.pointsPerSide)
        var black = [Int](repeating: 0, count: Self.pointsPerSide)
        white[0] = Self.checkersPerPlayer
        black[0] = Self.checkersPerPlayer
        points = [.white: white, .black: black]
        borneOff = [.white: 0, .black: 0]
        turn = .white
        dice = []
        lastRoll = []
        winner = nil
        selectedPoint = nil
        rollDice()
    }

    /// Maps a player's own relative point (0 = head, 23 = last before home exit)
    /// to a shared physical board index 0...23 for rendering. White and Black
    /// start on opposite corners (offset by 12).
    func physicalIndex(color: NardyColor, relative: Int) -> Int {
        let offset = color == .white ? 0 : Self.pointsPerSide / 2
        return (relative + offset) % Self.pointsPerSide
    }

    func rollDice() {
        let d1 = Int.random(in: 1...6)
        let d2 = Int.random(in: 1...6)
        lastRoll = [d1, d2]
        dice = d1 == d2 ? [d1, d1, d1, d1] : [d1, d2]
        if legalMoves(for: turn).isEmpty {
            // No legal moves at all this turn — pass.
            endTurn()
        }
    }

    private func isHome(_ color: NardyColor, _ relative: Int) -> Bool {
        relative >= Self.homeStart
    }

    private func allInHome(_ color: NardyColor) -> Bool {
        guard let pts = points[color] else { return false }
        for i in 0..<Self.homeStart where pts[i] > 0 { return false }
        return true
    }

    struct NardyMove {
        var from: Int
        var die: Int
        var isBearOff: Bool
    }

    func legalMoves(for color: NardyColor) -> [NardyMove] {
        guard let pts = points[color], winner == nil else { return [] }
        var moves: [NardyMove] = []
        let uniqueDice = Set(dice)
        let home = allInHome(color)
        for die in uniqueDice {
            for i in 0..<Self.pointsPerSide where pts[i] > 0 {
                let target = i + die
                if target < Self.pointsPerSide {
                    moves.append(NardyMove(from: i, die: die, isBearOff: false))
                } else if home {
                    // Exact bear-off, or overage allowed only if no checker further back.
                    if target == Self.pointsPerSide {
                        moves.append(NardyMove(from: i, die: die, isBearOff: true))
                    } else {
                        let hasFurtherBack = (Self.homeStart..<i).contains { pts[$0] > 0 }
                        if !hasFurtherBack {
                            moves.append(NardyMove(from: i, die: die, isBearOff: true))
                        }
                    }
                }
            }
        }
        return moves
    }

    /// Returns the relative points that currently have at least one legal move
    /// for any remaining die, for UI highlighting.
    func movablePoints(for color: NardyColor) -> Set<Int> {
        Set(legalMoves(for: color).map { $0.from })
    }

    /// Attempts to move the checker at `relative` point using the best available
    /// die (prefers an exact bear-off, otherwise the smallest usable die).
    func moveFrom(_ relative: Int) {
        guard turn == .white, winner == nil else { return }
        let candidates = legalMoves(for: .white).filter { $0.from == relative }
        guard !candidates.isEmpty else { return }
        let chosen = candidates.sorted { a, b in
            if a.isBearOff != b.isBearOff { return a.isBearOff }
            return a.die < b.die
        }.first!
        apply(chosen, color: .white)
    }

    /// Multiplayer: lets either color make the human move choice at `relative`,
    /// using the same tie-break heuristic as `moveFrom` (prefers an exact bear-off,
    /// otherwise the smallest usable die). `moveFrom` is hardcoded to `.white`
    /// because single-player always casts the local human as white; this version
    /// is used so a multiplayer guest playing black can move too.
    func humanMove(_ relative: Int, color: NardyColor) {
        guard turn == color, winner == nil else { return }
        let candidates = legalMoves(for: color).filter { $0.from == relative }
        guard !candidates.isEmpty else { return }
        let chosen = candidates.sorted { a, b in
            if a.isBearOff != b.isBearOff { return a.isBearOff }
            return a.die < b.die
        }.first!
        apply(chosen, color: color)
    }

    func apply(_ move: NardyMove, color: NardyColor) {
        guard var pts = points[color], pts[move.from] > 0 else { return }
        pts[move.from] -= 1
        if move.isBearOff {
            borneOff[color, default: 0] += 1
        } else {
            pts[move.from + move.die] += 1
        }
        points[color] = pts

        if let dieIndex = dice.firstIndex(of: move.die) {
            dice.remove(at: dieIndex)
        }

        if borneOff[color] == Self.checkersPerPlayer {
            winner = color
            return
        }

        if dice.isEmpty || legalMoves(for: color).isEmpty {
            endTurn()
        }
    }

    private func endTurn() {
        dice = []
        turn = turn == .white ? .black : .white
        rollDice()
    }

    func count(for color: NardyColor, at relative: Int) -> Int {
        points[color]?[relative] ?? 0
    }

    // MARK: - Multiplayer sync

    /// Replaces the current state wholesale with one received from the host, so a
    /// multiplayer guest mirrors the host's authoritative (and already-random)
    /// dice rolls instead of generating its own. The host device runs the real
    /// `reset()`/`apply()`/`rollDice()` logic exactly as in single-player and
    /// broadcasts the result after every change; the guest's own engine instance
    /// never calls those random-dice methods itself.
    func applyDeal(whitePoints: [Int], blackPoints: [Int], whiteBorneOff: Int, blackBorneOff: Int, turn: NardyColor, dice: [Int], lastRoll: [Int], winner: NardyColor?) {
        points = [.white: whitePoints, .black: blackPoints]
        borneOff = [.white: whiteBorneOff, .black: blackBorneOff]
        self.turn = turn
        self.dice = dice
        self.lastRoll = lastRoll
        self.winner = winner
        selectedPoint = nil
    }
}

// MARK: - Simple AI (Black)

extension NardyEngine {
    func playBotTurnIfNeeded() {
        guard turn == .black, winner == nil else { return }
        while turn == .black, winner == nil, !dice.isEmpty {
            // Prefer bearing off, then advancing the most-behind checker furthest.
            let moves = legalMoves(for: .black).sorted { a, b in
                if a.isBearOff != b.isBearOff { return a.isBearOff }
                if a.from != b.from { return a.from < b.from }
                return a.die > b.die
            }
            guard let chosen = moves.first else {
                endTurn()
                break
            }
            apply(chosen, color: .black)
        }
    }
}
