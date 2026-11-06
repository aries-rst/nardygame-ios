import SwiftUI

enum DailyPuzzlePhase {
    case loading, alreadySolved, intro, playing, failed, solved, unavailable
}

/// Daily bear-off puzzle (always Long Nardy, solo) — same Mulberry32-seeded
/// generator as Android, so both platforms get the identical puzzle each day.
/// Mirrors GameController.kt's startPuzzle/puzzleNextTurn/puzzleSolved flow.
/// Uses @Published (like NardyGameController) rather than @State directly on
/// the reference-type NGState, so every mutation reliably triggers a redraw.
final class DailyPuzzleController: ObservableObject {
    @Published var phase: DailyPuzzlePhase = .loading
    @Published var state: NGState = NEngine.newGame(.long)
    @Published var turnIndex = 0
    @Published var hintFrom: Int?
    @Published var dailyRecord = NardyDaily.info()

    var puzzle: NPuzzle?
    private var undoStack: [NGState] = []
    private var isReplay = false

    let dateNum = NardyDaily.todayNum()

    func checkToday() {
        dailyRecord = NardyDaily.info()
        if dailyRecord.last == dateNum {
            phase = .alreadySolved
        } else {
            start(replay: false)
        }
    }

    func start(replay: Bool) {
        isReplay = replay
        phase = .loading
        let d = dateNum
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let pz = NEngine.makePuzzle(d)
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let pz = pz else { self.phase = .unavailable; return }
                self.puzzle = pz
                self.phase = .intro
            }
        }
    }

    func beginPlaying() {
        guard let pz = puzzle else { return }
        let s = pz.start.copy()
        state = NEngine.setDice(s, pz.dice[0][0], pz.dice[0][1])
        turnIndex = 0
        undoStack = []
        hintFrom = nil
        phase = .playing
    }

    var movablePoints: Set<Int> {
        var pts = Set<Int>()
        for step in NEngine.legalSteps(state) where step.from >= 0 {
            pts.insert(NEngine.boardOf(.long, 0, step.from))
        }
        return pts
    }

    var canUndo: Bool { !undoStack.isEmpty }

    func tapPoint(_ physical: Int) {
        let ownFrom = NEngine.pathOf(.long, 0, physical)
        let candidates = NEngine.legalSteps(state).filter { $0.from == ownFrom }
        guard let chosen = candidates.sorted(by: { a, b in
            let aOff = a.to == 24; let bOff = b.to == 24
            if aOff != bOff { return aOff }
            return a.die < b.die
        }).first else { return }
        undoStack.append(state)
        hintFrom = nil
        state = chosen.state
        if state.off[0] == 15 || state.left.isEmpty || NEngine.legalSteps(state).isEmpty {
            finishTurnAndCheck()
        }
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        state = prev
        hintFrom = nil
    }

    func hint() {
        guard let pz = puzzle else { return }
        if let step = NEngine.puzzleHint(state, pz.dice, turnIndex, pz.turns) {
            hintFrom = step.from >= 0 ? NEngine.boardOf(.long, 0, step.from) : nil
        }
    }

    private func finishTurnAndCheck() {
        guard let pz = puzzle else { return }
        if state.off[0] == 15 {
            if !isReplay { NardyDaily.recordSolved(dateNum: dateNum) }
            dailyRecord = NardyDaily.info()
            phase = .solved
            return
        }
        turnIndex += 1
        if turnIndex >= pz.turns {
            phase = .failed
            return
        }
        let ended = NEngine.endTurn(state)
        state = NEngine.setDice(ended, pz.dice[turnIndex][0], pz.dice[turnIndex][1])
        undoStack = []
    }
}

struct DailyPuzzleView: View {
    @ObservedObject private var lang = AppLang.shared
    @StateObject private var c = DailyPuzzleController()
    @Environment(\.dismiss) private var dismiss

    private let night = Color(red: 0.05, green: 0.16, blue: 0.20)
    private let gold = Color(red: 0.85, green: 0.62, blue: 0.22)
    private let turquoise = Color(red: 0.17, green: 0.56, blue: 0.55)
    private let sand = Color(red: 0.95, green: 0.90, blue: 0.78)
    private let boardDark = Color(red: 0.10, green: 0.26, blue: 0.27)
    private let boardLight = Color(red: 0.15, green: 0.35, blue: 0.35)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 6)

    var body: some View {
        NavigationStack {
            ZStack {
                night.ignoresSafeArea()
                content
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Close", "Закрыть")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { c.checkToday() }
    }

    @ViewBuilder
    private var content: some View {
        switch c.phase {
        case .loading:
            ProgressView().tint(gold)
        case .alreadySolved:
            statusCard(
                emoji: "✅",
                title: t("Solved today", "Решено сегодня"),
                subtitle: t("Streak: \(c.dailyRecord.streak)", "Серия: \(c.dailyRecord.streak)"),
                primary: (t("Replay", "Сыграть снова"), { c.start(replay: true) }),
                secondary: (t("Close", "Закрыть"), { dismiss() })
            )
        case .unavailable:
            statusCard(
                emoji: "🧩",
                title: t("No puzzle today", "Сегодня нет задачи"),
                subtitle: t("Please try again later.", "Попробуйте позже."),
                primary: (t("Close", "Закрыть"), { dismiss() }),
                secondary: nil
            )
        case .intro:
            if let pz = c.puzzle {
                statusCard(
                    emoji: "🧩",
                    title: t("Puzzle of the Day", "Задача дня") + " · " + NardyDaily.fmtDate(c.dateNum),
                    subtitle: t("Bear off all checkers in \(pz.turns) turns.", "Выведите все шашки за \(pz.turns) ход(ов)."),
                    primary: (t("Start", "Начать"), { c.beginPlaying() }),
                    secondary: nil
                )
            }
        case .playing:
            playingView
        case .failed:
            statusCard(
                emoji: "❌",
                title: t("Not solved", "Не решено"),
                subtitle: c.puzzle != nil ? t("Goal: finish in \(c.puzzle!.turns) turns.", "Цель: уложиться в \(c.puzzle!.turns) ход(ов).") : "",
                primary: (t("Retry", "Заново"), { c.start(replay: false) }),
                secondary: (t("Close", "Закрыть"), { dismiss() })
            )
        case .solved:
            statusCard(
                emoji: "🎉",
                title: t("Solved!", "Решено!"),
                subtitle: t("\(c.turnIndex + 1) / \(c.puzzle?.turns ?? 0) turns · Streak: \(c.dailyRecord.streak)", "\(c.turnIndex + 1) / \(c.puzzle?.turns ?? 0) ход(ов) · Серия: \(c.dailyRecord.streak)"),
                primary: (t("Close", "Закрыть"), { dismiss() }),
                secondary: nil
            )
        }
    }

    private func statusCard(emoji: String, title: String, subtitle: String, primary: (String, () -> Void), secondary: (String, () -> Void)?) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Text(emoji).font(.system(size: 54))
            Text(title).font(.title3.bold()).foregroundStyle(sand).multilineTextAlignment(.center)
            if !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(sand.opacity(0.75)).multilineTextAlignment(.center)
            }
            Button(primary.0, action: primary.1)
                .font(.headline)
                .foregroundStyle(night)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Capsule().fill(gold))
            if let secondary = secondary {
                Button(secondary.0, action: secondary.1)
                    .font(.subheadline)
                    .foregroundStyle(sand.opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Board

    private var playingView: some View {
        let movable = c.movablePoints
        return VStack(spacing: 12) {
            if let pz = c.puzzle {
                Text(t("Turn \(c.turnIndex + 1) / \(pz.turns)", "Ход \(c.turnIndex + 1) / \(pz.turns)"))
                    .font(.caption.bold())
                    .foregroundStyle(turquoise)
            }
            Text(t("Off: \(c.state.off[0])/15", "Выведено: \(c.state.off[0])/15"))
                .font(.headline)
                .foregroundStyle(gold)
            HStack(spacing: 10) {
                ForEach(Array(c.state.dice.enumerated()), id: \.offset) { _, value in
                    Text("\(value)")
                        .font(.title3.bold())
                        .frame(width: 34, height: 34)
                        .background(gold)
                        .foregroundStyle(night)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
                Button { c.undo() } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill").font(.title2)
                }
                .disabled(!c.canUndo)
                Button { c.hint() } label: {
                    Image(systemName: "lightbulb.circle.fill").font(.title2)
                }
            }
            .foregroundStyle(sand)
            .padding(.horizontal, 16)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0..<24, id: \.self) { physical in
                    puzzleCell(physical, movable: movable)
                }
            }
            .padding(8)
            .background(boardDark.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(gold.opacity(0.4), lineWidth: 1))
            .padding(.horizontal, 10)

            Spacer()
        }
        .padding(.top, 10)
    }

    private func puzzleCell(_ physical: Int, movable: Set<Int>) -> some View {
        let own = NEngine.pathOf(.long, 0, physical)
        let count = c.state.pos[0][own]
        let isMovable = movable.contains(physical)
        let isHint = c.hintFrom == physical
        return VStack(spacing: 2) {
            Text("\(physical + 1)")
                .font(.system(size: 9))
                .foregroundStyle(sand.opacity(0.4))
            if count > 0 {
                ZStack {
                    Circle().fill(sand).frame(width: 22, height: 22)
                        .overlay(Circle().stroke(gold.opacity(0.6), lineWidth: 1))
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(night)
                }
            } else {
                Spacer().frame(height: 22)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.vertical, 4)
        .background((physical / 6) % 2 == 0 ? boardDark : boardLight)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isHint ? .yellow : (isMovable ? turquoise : .clear), lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            guard isMovable else { return }
            c.tapPoint(physical)
        }
    }
}

#Preview {
    DailyPuzzleView()
}
