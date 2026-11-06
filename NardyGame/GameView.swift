import SwiftUI

// MARK: - Network payloads (host-authoritative, same pattern as Durak/Domino's
// NetworkGameEngine: only the host ever rolls dice or mutates `NGState`; it
// broadcasts the full state after every change, and a guest sends small move
// intents back. The doubling cube is vs-bot only in this build — see
// `NardyGameController.offerDouble()`.)

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

struct NNetMessage: Codable {
    var deal: NStatePayload? = nil
    var intent: NIntent? = nil
    var rollRequest: Bool? = nil
}

/// Drives one match for every variant (long/short/tavla/plakoto/fevga) against
/// a bot, or over `MultiplayerManager` — seat 0 is always the local human in
/// single-player, or the host in multiplayer; seat 1 is the bot, or the guest.
final class NardyGameController: ObservableObject {
    @Published var state: NGState
    @Published var cubeOfferPending = false // vs-bot only: bot offered, human must respond
    @Published var winnerSeat: Int? = nil
    @Published var winnerPoints: Int = 0

    let variant: NVariant
    let botLevel: Int
    let multiplayer: MultiplayerManager?
    let localSeat: Int // 0 if single-player or host; 0 or 1 if multiplayer guest resolved to 1

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
        state.turn == seat && state.dice.isEmpty && winnerSeat == nil && !cubeOfferPending
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
        } else if localSeat == 0 {
            guard seat == 0 else { return }
            performRoll()
            broadcast()
        } else {
            multiplayer?.send(NNetMessage(rollRequest: true))
        }
    }

    private func performRoll() {
        state = NEngine.setDice(state, NEngine.fairDie(), NEngine.fairDie())
        if NEngine.legalSteps(state).isEmpty {
            state = NEngine.endTurn(state)
            checkWinner()
        }
    }

    // MARK: - Doubling cube (vs bot only)

    func offerDouble() {
        guard canOfferDouble(seat: 0) else { return }
        if NEngine.botShouldTake(state, 1) {
            state.cube *= 2
            state.cubeOwner = 1
            objectWillChange.send()
        } else {
            winnerSeat = 0
            winnerPoints = state.cube
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
            winnerSeat = 1
            winnerPoints = state.cube
        }
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
            winnerSeat = w
            winnerPoints = NEngine.winScore(state, w) * state.cube
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
        state = NEngine.setDice(state, NEngine.fairDie(), NEngine.fairDie())
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
        if multiplayer != nil && localSeat == 0 { broadcast() }
    }

    // MARK: - Networking plumbing

    private func broadcast() {
        multiplayer?.send(NNetMessage(deal: NStatePayload(state)))
    }

    private func setupReceiver() {
        guard let mp = multiplayer else { return }
        mp.onReceive = { [weak self] data in
            guard let self = self, let msg = try? JSONDecoder().decode(NNetMessage.self, from: data) else { return }
            DispatchQueue.main.async {
                if let deal = msg.deal {
                    self.state = deal.toState()
                    self.checkWinner()
                } else if let intent = msg.intent, self.localSeat == 0 {
                    self.hostApplyIntent(intent)
                } else if msg.rollRequest == true, self.localSeat == 0 {
                    self.hostApplyRollRequest()
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

    private func hostApplyRollRequest() {
        guard state.turn == 1, state.dice.isEmpty, winnerSeat == nil else { return }
        performRoll()
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
