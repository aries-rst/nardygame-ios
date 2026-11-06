import SwiftUI
import CryptoKit
import Security

// MARK: - Network payloads (host-authoritative, same pattern as Durak/Domino's
// NetworkGameEngine: only the host ever mutates `NGState`; it broadcasts the
// full state after every change, and a guest sends small move intents back.
// The doubling cube is vs-bot only in this build — see
// `NardyGameController.offerDouble()`. Dice VALUES, though, are never picked
// by either side alone: see `FairDice` below, a 1:1 port of Android's
// commit-reveal protocol in NetPlay.kt.)

struct NStatePayload: Codable {
    var variant: NVariant
    var pos0: [Int]; var pos1: [Int]
    var pin0: [Int]; var pin1: [Int]
    var frozen: [Int]
    var bar: [Int]
    var off: [Int]
    var turn: Int
    var dice: [Int]
    var left: [Int]
    var headUsed: Int
    var turnsTaken: [Int]
    var mother: Int
    var cube: Int
    var cubeOwner: Int
    // Carried alongside the state so a win by cube-drop (not detectable from
    // NGState alone) reaches the other device too.
    var winnerSeat: Int? = nil
    var winnerPoints: Int? = nil

    init(_ s: NGState) {
        variant = s.v
        pos0 = s.pos[0]; pos1 = s.pos[1]
        pin0 = s.pin[0]; pin1 = s.pin[1]
        frozen = s.frozen
        bar = s.bar
        off = s.off
        turn = s.turn
        dice = s.dice
        left = s.left
        headUsed = s.headUsed
        turnsTaken = s.turnsTaken
        mother = s.mother
        cube = s.cube
        cubeOwner = s.cubeOwner
    }

    func toState() -> NGState {
        NGState(v: variant, pos: [pos0, pos1], pin: [pin0, pin1], frozen: frozen, bar: bar, off: off,
                turn: turn, dice: dice, left: left, headUsed: headUsed, turnsTaken: turnsTaken,
                puzzle: false, lastMove: nil, mother: mother, cube: cube, cubeOwner: cubeOwner)
    }
}

struct NIntent: Codable {
    var from: Int
    var die: Int
}

struct NDiceCommit: Codable { var n: String; var hash: String }
struct NDiceSeed: Codable { var n: String; var seed: String }

struct NNetMessage: Codable {
    var deal: NStatePayload? = nil
    var intent: NIntent? = nil
    // Cube over network: the mover sends `cubeOffer`; since only the host
    // mutates shared state, a guest's decision travels back as `cubeDecision`
    // for the host to apply (see NardyGameController's network cube methods).
    var cubeOffer: Bool? = nil
    var cubeDecision: Bool? = nil
    // Fair dice (commit-reveal) — see `FairDice` and `NardyGameController`'s
    // roll methods for the three-message exchange these carry.
    var diceCommit: NDiceCommit? = nil
    var diceSeedAnswer: NDiceSeed? = nil
    var diceReveal: NDiceSeed? = nil
}

/// Fair dice for two phones (commit–reveal) — 1:1 port of Android's `FairDice`
/// object in NetPlay.kt. The roller commits to sha256(seedA); the other side
/// answers with its own seedB (chosen before it has seen seedA); the roller
/// then reveals seedA. Neither side can bias the result: the committer can't
/// change seedA after seeing seedB (the hash already locked it in), and the
/// answerer picked seedB before it ever saw seedA. dice = f(seedA, seedB, n).
/// `n` is a per-exchange nonce (a UUID here, rather than Android's monotonic
/// counter — the two platforms never play cross-protocol, so only uniqueness
/// within one match matters).
enum FairDice {
    static func seed() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Rejection-sampled against 252 (6*42) so every die face stays equally
    /// likely, exactly like the Kotlin original's `v < 252` guard.
    static func dice(_ seedA: String, _ seedB: String, _ n: String) -> (Int, Int) {
        var out: [Int] = []
        var round = 0
        while out.count < 2 {
            let input = "\(seedA):\(seedB):\(n):\(round)"
            let digest = SHA256.hash(data: Data(input.utf8))
            for byte in digest {
                let v = Int(byte)
                if v < 252 && out.count < 2 { out.append(v % 6 + 1) }
            }
            round += 1
        }
        return (out[0], out[1])
    }
}

/// Drives one match for every variant (long/short/tavla/plakoto/fevga) against
/// a bot, or over `MultiplayerManager` — seat 0 is always the local human in
/// single-player, or the host in multiplayer; seat 1 is the bot, or the guest.
final class NardyGameController: ObservableObject {
    @Published var state: NGState
    @Published var cubeOfferPending = false // vs-bot only: bot offered, human must respond
    @Published var incomingCubeOffer = false // network only: the opponent offered, this device's human must respond
    @Published var winnerSeat: Int? = nil
    @Published var winnerPoints: Int = 0
    @Published var isRollPending = false // network only: fair-dice commit/reveal exchange in flight

    let variant: NVariant
    let botLevel: Int
    let multiplayer: MultiplayerManager?
    let localSeat: Int // 0 if single-player or host; 0 or 1 if multiplayer guest resolved to 1

    // Fair-dice exchange state (see `FairDice`): at most one of these is set
    // at a time, depending on whether this device committed (is rolling) or
    // is the one answering someone else's commit.
    private var myRollSeed: (n: String, seed: String)? = nil
    private var pendingAnswer: (n: String, hash: String, seed: String)? = nil

    init(variant: NVariant, botLevel: Int, multiplayer: MultiplayerManager? = nil, localSeat: Int = 0) {
        self.variant = variant
        self.botLevel = botLevel
        self.multiplayer = multiplayer
        self.localSeat = localSeat
        self.state = NEngine.newGame(variant)
        setupReceiver()
        if multiplayer != nil && localSeat == 0 {
            broadcast()
        }
    }

    // MARK: - Turn queries

    func canRoll(seat: Int) -> Bool {
        state.turn == seat && state.dice.isEmpty && winnerSeat == nil && !cubeOfferPending && !isRollPending
    }

    func canOfferDouble(seat: Int) -> Bool {
        multiplayer == nil && seat == 0 && NEngine.canOffer(state, 0, false) && state.dice.isEmpty && winnerSeat == nil
    }

    /// Physical board points (0...23) the given seat may currently move a
    /// checker from, plus a synthetic "bar" entry when true is included.
    func movable(seat: Int) -> (points: Set<Int>, bar: Bool) {
        guard state.turn == seat, winnerSeat == nil, !state.dice.isEmpty else { return ([], false) }
        var pts = Set<Int>(); var bar = false
        for step in NEngine.legalSteps(state) {
            if step.from == -1 { bar = true }
            else { pts.insert(NEngine.boardOf(variant, seat, step.from)) }
        }
        return (pts, bar)
    }

    // MARK: - Rolling

    func requestRoll(seat: Int) {
        guard canRoll(seat: seat) else { return }
        if multiplayer == nil {
            performRoll()
            botTurnIfNeeded()
        } else {
            guard seat == localSeat else { return }
            beginFairRoll()
        }
    }

    private func performRoll() {
        let a = NEngine.fairDie(); let b = NEngine.fairDie()
        NardyStats.shared.recordRoll(isBot: false, a, b)
        applyRolledDice(a, b)
    }

    private func applyRolledDice(_ a: Int, _ b: Int) {
        state = NEngine.setDice(state, a, b)
        if NEngine.legalSteps(state).isEmpty {
            state = NEngine.endTurn(state)
            checkWinner()
        }
    }

    // MARK: - Fair dice over network (see `FairDice`)

    /// Kick off a commit-reveal exchange for this device's own roll. Whoever
    /// is NOT rolling answers automatically from `setupReceiver`'s `diceCommit`
    /// branch below.
    private func beginFairRoll() {
        guard !isRollPending else { return }
        isRollPending = true
        let seedA = FairDice.seed()
        let n = UUID().uuidString
        myRollSeed = (n, seedA)
        multiplayer?.send(NNetMessage(diceCommit: NDiceCommit(n: n, hash: FairDice.sha(seedA))))
    }

    /// Only the host ever mutates the shared `state` (same invariant as every
    /// other mutation in this controller) — whichever device finishes the
    /// commit-reveal exchange computes the identical (a, b) locally, but only
    /// the host applies it and broadcasts; the guest just waits for that.
    private func applyFairRoll(_ a: Int, _ b: Int) {
        guard localSeat == 0 else { return }
        applyRolledDice(a, b)
        broadcast()
    }

    // MARK: - Doubling cube (vs bot only)

    func offerDouble() {
        guard canOfferDouble(seat: 0) else { return }
        if NEngine.botShouldTake(state, 1) {
            state.cube *= 2
            state.cubeOwner = 1
            objectWillChange.send()
        } else {
            endGameVsBot(winner: 0, points: state.cube)
        }
    }

    func respondToBotCubeOffer(accept: Bool) {
        guard cubeOfferPending else { return }
        cubeOfferPending = false
        if accept {
            state.cube *= 2
            state.cubeOwner = 0
            objectWillChange.send()
            playBotTurn()
        } else {
            endGameVsBot(winner: 1, points: state.cube)
        }
    }

    /// Records vs-bot stats once, from every path that can end such a game
    /// (an engine win, or either side dropping a cube offer).
    private func endGameVsBot(winner: Int, points: Int) {
        winnerSeat = winner
        winnerPoints = points
        NardyStats.shared.recordResult(variant: variant, level: botLevel, won: winner == 0)
    }

    // MARK: - Doubling cube over network (both seats; only the host mutates
    // shared state, so a non-host's decision is relayed back for the host to apply)

    func canOfferDoubleNetwork(seat: Int) -> Bool {
        multiplayer != nil && state.turn == seat && NEngine.canOffer(state, seat, false)
            && state.dice.isEmpty && winnerSeat == nil && !incomingCubeOffer
    }

    func offerDoubleNetwork(seat: Int) {
        guard canOfferDoubleNetwork(seat: seat) else { return }
        multiplayer?.send(NNetMessage(cubeOffer: true))
    }

    /// Called on whichever device is showing the "opponent offered to double" alert.
    func respondToNetworkCubeOffer(accept: Bool) {
        guard incomingCubeOffer else { return }
        incomingCubeOffer = false
        if localSeat == 0 {
            applyCubeDecision(accept: accept, offererSeat: 1)
        } else {
            multiplayer?.send(NNetMessage(cubeDecision: accept))
        }
    }

    /// Host-only: apply a cube accept/drop and broadcast the result.
    private func applyCubeDecision(accept: Bool, offererSeat: Int) {
        if accept {
            state.cube *= 2
            state.cubeOwner = 1 - offererSeat
            objectWillChange.send()
        } else {
            winnerSeat = offererSeat
            winnerPoints = state.cube
        }
        broadcast()
    }

    // MARK: - Human move

    /// `physical` is a board point 0...23, or -1 to enter from the bar.
    func tapPoint(_ physical: Int, seat: Int) {
        guard winnerSeat == nil, state.turn == seat, !state.dice.isEmpty else { return }
        let ownFrom = physical == -1 ? -1 : NEngine.pathOf(variant, seat, physical)
        let candidates = NEngine.legalSteps(state).filter { $0.from == ownFrom }
        guard let chosen = candidates.sorted(by: { a, b in
            let aOff = a.to == 24; let bOff = b.to == 24
            if aOff != bOff { return aOff }
            return a.die < b.die
        }).first else { return }

        if multiplayer == nil {
            applyAndContinue(chosen.state)
            botTurnIfNeeded()
        } else if localSeat == 0 {
            guard seat == 0 else { return }
            applyAndContinue(chosen.state)
            broadcast()
        } else {
            guard seat == localSeat else { return }
            multiplayer?.send(NNetMessage(intent: NIntent(from: ownFrom, die: chosen.die)))
        }
    }

    private func applyAndContinue(_ next: NGState) {
        state = next
        if state.left.isEmpty || NEngine.legalSteps(state).isEmpty {
            state = NEngine.endTurn(state)
            checkWinner()
        }
    }

    private func checkWinner() {
        let w = NEngine.winner(state)
        if w >= 0 {
            let points = NEngine.winScore(state, w) * state.cube
            if multiplayer == nil {
                endGameVsBot(winner: w, points: points)
            } else {
                winnerSeat = w
                winnerPoints = points
            }
        }
    }

    // MARK: - Bot (single-player only)

    private func botTurnIfNeeded() {
        guard multiplayer == nil, state.turn == 1, winnerSeat == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, self.winnerSeat == nil else { return }
            if NEngine.canOffer(self.state, 1, false) && NEngine.botShouldDouble(self.state, 1) {
                self.cubeOfferPending = true
                return
            }
            self.playBotTurn()
        }
    }

    private func playBotTurn() {
        let a = NEngine.fairDie(); let b = NEngine.fairDie()
        NardyStats.shared.recordRoll(isBot: true, a, b)
        state = NEngine.setDice(state, a, b)
        let seq = NEngine.aiChoose(state, botLevel)
        if let last = seq.last { state = last.state }
        state = NEngine.endTurn(state)
        checkWinner()
    }

    func newMatch() {
        state = NEngine.newGame(variant)
        winnerSeat = nil
        winnerPoints = 0
        cubeOfferPending = false
        incomingCubeOffer = false
        isRollPending = false
        myRollSeed = nil
        pendingAnswer = nil
        if multiplayer != nil && localSeat == 0 { broadcast() }
    }

    // MARK: - Networking plumbing

    private func broadcast() {
        var payload = NStatePayload(state)
        if let ws = winnerSeat {
            payload.winnerSeat = ws
            payload.winnerPoints = winnerPoints
        }
        multiplayer?.send(NNetMessage(deal: payload))
    }

    private func setupReceiver() {
        guard let mp = multiplayer else { return }
        mp.onReceive = { [weak self] data in
            guard let self = self, let msg = try? JSONDecoder().decode(NNetMessage.self, from: data) else { return }
            DispatchQueue.main.async {
                if let deal = msg.deal {
                    self.state = deal.toState()
                    if let ws = deal.winnerSeat {
                        self.winnerSeat = ws
                        self.winnerPoints = deal.winnerPoints ?? 0
                    } else {
                        self.checkWinner()
                    }
                } else if let intent = msg.intent, self.localSeat == 0 {
                    self.hostApplyIntent(intent)
                } else if msg.cubeOffer == true {
                    self.incomingCubeOffer = true
                } else if let decision = msg.cubeDecision, self.localSeat == 0 {
                    self.applyCubeDecision(accept: decision, offererSeat: 0)
                } else if let commit = msg.diceCommit {
                    // The other device is rolling; answer with our own seed,
                    // chosen before we've seen theirs.
                    let seedB = FairDice.seed()
                    self.pendingAnswer = (commit.n, commit.hash, seedB)
                    self.multiplayer?.send(NNetMessage(diceSeedAnswer: NDiceSeed(n: commit.n, seed: seedB)))
                } else if let answer = msg.diceSeedAnswer, let mine = self.myRollSeed, mine.n == answer.n {
                    // We're the roller: now that both seeds exist, reveal ours
                    // and compute the (now-fixed) result.
                    self.myRollSeed = nil
                    self.isRollPending = false
                    self.multiplayer?.send(NNetMessage(diceReveal: NDiceSeed(n: mine.n, seed: mine.seed)))
                    let (a, b) = FairDice.dice(mine.seed, answer.seed, mine.n)
                    self.applyFairRoll(a, b)
                } else if let reveal = msg.diceReveal, let pending = self.pendingAnswer, pending.n == reveal.n {
                    // We were the answerer: verify the commitment before
                    // trusting the revealed seed, then compute the same result.
                    self.pendingAnswer = nil
                    guard FairDice.sha(reveal.seed) == pending.hash else { return }
                    let (a, b) = FairDice.dice(reveal.seed, pending.seed, reveal.n)
                    self.applyFairRoll(a, b)
                }
            }
        }
    }

    private func hostApplyIntent(_ intent: NIntent) {
        guard state.turn == 1, winnerSeat == nil else { return }
        let candidates = NEngine.legalSteps(state).filter { $0.from == intent.from && $0.die == intent.die }
        guard let chosen = candidates.first else { return }
        applyAndContinue(chosen.state)
        broadcast()
    }
}

// MARK: - Board UI

struct GameView: View {
    @ObservedObject var store: StoreManager
    @ObservedObject private var lang = AppLang.shared
    @StateObject private var controller: NardyGameController
    @Environment(\.dismiss) private var dismiss

    private let localSeat: Int

    private let night = Color(red: 0.05, green: 0.16, blue: 0.20)
    private let gold = Color(red: 0.85, green: 0.62, blue: 0.22)
    private let turquoise = Color(red: 0.17, green: 0.56, blue: 0.55)
    private let sand = Color(red: 0.95, green: 0.90, blue: 0.78)
    private let boardDark = Color(red: 0.10, green: 0.26, blue: 0.27)
    private let boardLight = Color(red: 0.15, green: 0.35, blue: 0.35)

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 6)

    init(store: StoreManager, variant: NVariant, botLevel: Int, multiplayer: MultiplayerManager? = nil, localSeat: Int = 0) {
        self.store = store
        self.localSeat = localSeat
        _controller = StateObject(wrappedValue: NardyGameController(
            variant: variant, botLevel: botLevel, multiplayer: multiplayer, localSeat: localSeat))
    }

    private var mySeat: Int { localSeat }

    var body: some View {
        ZStack {
            night.ignoresSafeArea()
            VStack(spacing: 12) {
                header
                cubeRow
                diceAndBarRow
                boardView
                    .padding(.horizontal, 10)
                footer
                Spacer()
            }
            .padding(.top, 10)
        }
        .alert(t("Double offered", "Предложено удвоение"), isPresented: $controller.cubeOfferPending) {
            Button(t("Take", "Принять")) { controller.respondToBotCubeOffer(accept: true) }
            Button(t("Drop", "Отказаться"), role: .destructive) { controller.respondToBotCubeOffer(accept: false) }
        } message: {
            Text(t("The bot offers to double the stakes to \(controller.state.cube * 2).", "Бот предлагает удвоить ставку до \(controller.state.cube * 2)."))
        }
        .alert(t("Double offered", "Предложено удвоение"), isPresented: $controller.incomingCubeOffer) {
            Button(t("Take", "Принять")) { controller.respondToNetworkCubeOffer(accept: true) }
            Button(t("Drop", "Отказаться"), role: .destructive) { controller.respondToNetworkCubeOffer(accept: false) }
        } message: {
            Text(t("Your opponent offers to double the stakes to \(controller.state.cube * 2).", "Соперник предлагает удвоить ставку до \(controller.state.cube * 2)."))
        }
        .alert(t("Game Over", "Игра окончена"), isPresented: Binding(get: { controller.winnerSeat != nil }, set: { _ in })) {
            Button(t("New Game", "Новая игра")) { controller.newMatch() }
            Button(t("To Menu", "В меню")) { dismiss() }
        } message: {
            Text(alertMessage)
        }
    }

    private var variantTitle: String {
        switch controller.variant {
        case .long: return t("Long Nardy", "Длинные нарды")
        case .short: return t("Backgammon", "Короткие нарды")
        case .tavla: return t("Tavla", "Тавла")
        case .plakoto: return t("Plakoto", "Плакото")
        case .fevga: return t("Fevga", "Февга")
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(variantTitle)
                .font(.caption.bold())
                .foregroundStyle(turquoise)
            HStack {
                Text(t("White off: \(controller.state.off[0])/15", "Белые вне: \(controller.state.off[0])/15"))
                    .foregroundStyle(sand)
                Spacer()
                Text(headerTurnText)
                    .font(.headline)
                    .foregroundStyle(gold)
                Spacer()
                Text(t("Black off: \(controller.state.off[1])/15", "Чёрные вне: \(controller.state.off[1])/15"))
                    .foregroundStyle(sand)
            }
            .font(.caption)
        }
        .padding(.horizontal, 16)
    }

    private var headerTurnText: String {
        if controller.multiplayer != nil {
            return controller.state.turn == mySeat ? t("Your turn", "Ваш ход") : t("Opponent's turn", "Ход соперника")
        }
        return controller.state.turn == 0 ? t("Your turn", "Ваш ход") : t("Bot's turn", "Ход бота")
    }

    private var alertMessage: String {
        guard let w = controller.winnerSeat else { return "" }
        let who: String
        if controller.multiplayer != nil {
            who = w == mySeat ? t("You won!", "Вы победили!") : t("Opponent won!", "Соперник победил!")
        } else {
            who = w == 0 ? t("You won!", "Вы победили!") : t("Bot won!", "Бот победил!")
        }
        return "\(who) (\(controller.winnerPoints) \(t("pts", "очк.")))"
    }

    @ViewBuilder
    private var cubeRow: some View {
        if controller.canOfferDouble(seat: mySeat) {
            Button {
                controller.offerDouble()
            } label: {
                Label(t("Double (cube: \(controller.state.cube))", "Удвоить (куб: \(controller.state.cube))"), systemImage: "cube")
                    .font(.caption.bold())
                    .foregroundStyle(night)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(gold))
            }
        } else if controller.canOfferDoubleNetwork(seat: mySeat) {
            Button {
                controller.offerDoubleNetwork(seat: mySeat)
            } label: {
                Label(t("Double (cube: \(controller.state.cube))", "Удвоить (куб: \(controller.state.cube))"), systemImage: "cube")
                    .font(.caption.bold())
                    .foregroundStyle(night)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(gold))
            }
        } else if controller.variant == .short && controller.state.cube > 1 {
            Text(t("Cube: \(controller.state.cube)", "Куб: \(controller.state.cube)"))
                .font(.caption.bold())
                .foregroundStyle(gold)
        }
    }

    private var diceAndBarRow: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(Array(controller.state.dice.enumerated()), id: \.offset) { _, value in
                    Text("\(value)")
                        .font(.title3.bold())
                        .frame(width: 34, height: 34)
                        .background(gold)
                        .foregroundStyle(night)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            if controller.canRoll(seat: mySeat) {
                Button {
                    controller.requestRoll(seat: mySeat)
                } label: {
                    Label(t("Roll", "Бросить"), systemImage: "dice.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(night)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(turquoise))
                }
            } else if controller.isRollPending {
                Label(t("Fair roll…", "Честный бросок…"), systemImage: "checkmark.shield")
                    .font(.caption.bold())
                    .foregroundStyle(turquoise)
            }
            Spacer()
            if controller.state.bar[0] > 0 || controller.state.bar[1] > 0 {
                barButton
            }
        }
        .frame(minHeight: 34)
    }

    private var barButton: some View {
        let movable = movableInfo
        let canEnter = movable.bar && controller.state.bar[mySeat] > 0
        return Button {
            guard canEnter else { return }
            controller.tapPoint(-1, seat: mySeat)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                if controller.state.bar[0] > 0 { checkerBadge(count: controller.state.bar[0], color: sand) }
                if controller.state.bar[1] > 0 { checkerBadge(count: controller.state.bar[1], color: Color(white: 0.2)) }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(canEnter ? turquoise : .clear, lineWidth: 2))
            )
        }
        .disabled(!canEnter)
    }

    private var movableInfo: (points: Set<Int>, bar: Bool) { controller.movable(seat: mySeat) }

    private var boardView: some View {
        let movable = movableInfo
        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(0..<24, id: \.self) { physical in
                pointCell(physical, movable: movable.points)
            }
        }
        .padding(8)
        .background(boardDark.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(gold.opacity(0.4), lineWidth: 1))
    }

    private func pointCell(_ physical: Int, movable: Set<Int>) -> some View {
        let v = controller.variant
        let whiteOwn = NEngine.pathOf(v, 0, physical)
        let blackOwn = NEngine.pathOf(v, 1, physical)
        let whiteCount = controller.state.pos[0][whiteOwn]
        let blackCount = controller.state.pos[1][blackOwn]
        let whitePinned = controller.state.pin[0][whiteOwn] != 0
        let blackPinned = controller.state.pin[1][blackOwn] != 0
        let isMovable = movable.contains(physical) && controller.state.turn == mySeat
        return VStack(spacing: 2) {
            Text("\(physical + 1)")
                .font(.system(size: 9))
                .foregroundStyle(sand.opacity(0.4))
            if whiteCount > 0 { checkerBadge(count: whiteCount, color: sand, pinned: whitePinned) }
            if blackCount > 0 { checkerBadge(count: blackCount, color: Color(white: 0.2), pinned: blackPinned) }
            if whiteCount == 0 && blackCount == 0 { Spacer().frame(height: 22) }
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.vertical, 4)
        .background((physical / 6) % 2 == 0 ? boardDark : boardLight)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isMovable ? turquoise : .clear, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            guard isMovable else { return }
            controller.tapPoint(physical, seat: mySeat)
        }
    }

    private func checkerBadge(count: Int, color: Color, pinned: Bool = false) -> some View {
        ZStack {
            Circle().fill(color).frame(width: 22, height: 22)
                .overlay(Circle().stroke(pinned ? .red : gold.opacity(0.6), lineWidth: pinned ? 2 : 1))
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color == sand ? night : sand)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if controller.multiplayer == nil {
                Button {
                    controller.newMatch()
                } label: {
                    Label(t("New Game", "Новая игра"), systemImage: "arrow.counterclockwise")
                }
            }
            Spacer()
            if let mp = controller.multiplayer {
                Text(multiplayerStatusText(mp))
                    .font(.caption)
                    .foregroundStyle(sand.opacity(0.6))
            } else if !store.isPremium {
                Text(t("Ads shown in free version", "Реклама в бесплатной версии"))
                    .font(.caption)
                    .foregroundStyle(sand.opacity(0.5))
            }
        }
        .foregroundStyle(sand)
        .padding(.horizontal, 18)
    }

    private func multiplayerStatusText(_ mp: MultiplayerManager) -> String {
        if case .connected(let name) = mp.state {
            return t("Connected: \(name)", "Подключено: \(name)")
        }
        return t("Connection lost", "Соединение прервано")
    }
}

struct PremiumView: View {
    @ObservedObject var store: StoreManager
    @ObservedObject private var lang = AppLang.shared
    @Environment(\.dismiss) private var dismiss

    private let gold = Color(red: 0.85, green: 0.62, blue: 0.22)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(gold)
                    .padding(.top, 24)

                Text("Silk Road Premium")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    featureRow(t("No ads", "Без рекламы"))
                    featureRow(t("Local multiplayer over Wi-Fi/Bluetooth", "Локальный мультиплеер по Wi-Fi/Bluetooth"))
                    featureRow(t("One-time purchase — yours forever", "Разовая покупка — навсегда"))
                }
                .padding(.horizontal, 24)

                if store.isPremium {
                    Label(t("Premium already active", "Premium уже активен"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task { await store.purchasePremium() }
                    } label: {
                        Text(t("Buy for \(store.priceText)", "Купить за \(store.priceText)"))
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(gold)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)

                    Button(t("Restore Purchases", "Восстановить покупки")) {
                        Task { await store.restorePurchases() }
                    }
                    .font(.footnote)
                }

                if let err = store.purchaseErrorMessage {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Close", "Закрыть")) { dismiss() }
                }
            }
        }
    }

    private func featureRow(_ text: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text)
        }
    }
}

#Preview {
    GameView(store: StoreManager(), variant: .long, botLevel: 1)
}
