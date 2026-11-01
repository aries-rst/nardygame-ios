import SwiftUI

struct DealPayload: Codable {
    var whitePoints: [Int]
    var blackPoints: [Int]
    var whiteBorneOff: Int
    var blackBorneOff: Int
    var turn: NardyColor
    var dice: [Int]
    var lastRoll: [Int]
    var winner: NardyColor?
}

struct NetMessage: Codable {
    var moveRelative: Int? = nil
    var deal: DealPayload? = nil
}

struct GameView: View {
    @ObservedObject var store: StoreManager
    @ObservedObject private var lang = AppLang.shared
    @StateObject private var engine = NardyEngine()
    @Environment(\.dismiss) private var dismiss

    var multiplayer: MultiplayerManager? = nil
    var localColor: NardyColor = .white

    private let night = Color(red: 0.05, green: 0.16, blue: 0.20)
    private let gold = Color(red: 0.85, green: 0.62, blue: 0.22)
    private let turquoise = Color(red: 0.17, green: 0.56, blue: 0.55)
    private let sand = Color(red: 0.95, green: 0.90, blue: 0.78)
    private let boardDark = Color(red: 0.10, green: 0.26, blue: 0.27)
    private let boardLight = Color(red: 0.15, green: 0.35, blue: 0.35)

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 6)

    var body: some View {
        ZStack {
            night.ignoresSafeArea()
            VStack(spacing: 14) {
                header
                diceView
                boardView
                    .padding(.horizontal, 10)
                footer
                Spacer()
            }
            .padding(.top, 10)
        }
        .onChange(of: engine.turn) { _ in
            botTurnIfNeeded()
        }
        .onAppear {
            setupMultiplayerReceiver()
            botTurnIfNeeded()
        }
        .alert(t("Game Over", "Игра окончена"), isPresented: Binding(get: { engine.winner != nil }, set: { _ in })) {
            Button(t("New Game", "Новая игра")) { resetGame() }
            Button(t("To Menu", "В меню")) { dismiss() }
        } message: {
            Text(alertMessage)
        }
    }

    private var header: some View {
        HStack {
            Text(t("White off: \(engine.borneOff[.white] ?? 0)/15", "Белые вне: \(engine.borneOff[.white] ?? 0)/15"))
                .foregroundStyle(sand)
            Spacer()
            Text(headerTurnText)
                .font(.headline)
                .foregroundStyle(gold)
            Spacer()
            Text(t("Black off: \(engine.borneOff[.black] ?? 0)/15", "Чёрные вне: \(engine.borneOff[.black] ?? 0)/15"))
                .foregroundStyle(sand)
        }
        .font(.caption)
        .padding(.horizontal, 16)
    }

    private var headerTurnText: String {
        if multiplayer != nil {
            return engine.turn == localColor ? t("Your turn", "Ваш ход") : t("Opponent's turn", "Ход соперника")
        }
        return engine.turn == .white ? t("Your turn", "Ваш ход") : t("Bot's turn", "Ход бота")
    }

    private var alertMessage: String {
        guard let winner = engine.winner else { return "" }
        if multiplayer != nil {
            return winner == localColor ? t("You won!", "Вы победили!") : t("Opponent won!", "Соперник победил!")
        }
        return winner == .white ? t("You won!", "Вы победили!") : t("Bot won!", "Бот победил!")
    }

    private var diceView: some View {
        HStack(spacing: 10) {
            ForEach(Array(engine.dice.enumerated()), id: \.offset) { _, value in
                Text("\(value)")
                    .font(.title3.bold())
                    .frame(width: 34, height: 34)
                    .background(gold)
                    .foregroundStyle(night)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if engine.dice.isEmpty {
                Text(" ").frame(height: 34)
            }
        }
    }

    private var boardView: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(0..<24, id: \.self) { physical in
                pointCell(physical)
            }
        }
        .padding(8)
        .background(boardDark.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(gold.opacity(0.4), lineWidth: 1))
    }

    private func pointCell(_ physical: Int) -> some View {
        // White's relative index equals the physical index (offset 0).
        // Black's relative index is offset by 12.
        let whiteCount = engine.count(for: .white, at: physical)
        let blackRelative = (physical + 12) % 24
        let blackCount = engine.count(for: .black, at: blackRelative)
        let activeColor: NardyColor = multiplayer != nil ? localColor : .white
        let activeRelative = activeColor == .white ? physical : blackRelative
        let isMovable = engine.turn == activeColor && engine.movablePoints(for: activeColor).contains(activeRelative)
        let isSelected = engine.selectedPoint == physical

        return VStack(spacing: 2) {
            Text("\(physical + 1)")
                .font(.system(size: 9))
                .foregroundStyle(sand.opacity(0.45))
            if whiteCount > 0 {
                checkerBadge(count: whiteCount, color: sand)
            }
            if blackCount > 0 {
                checkerBadge(count: blackCount, color: Color(white: 0.2))
            }
            if whiteCount == 0 && blackCount == 0 {
                Spacer().frame(height: 22)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.vertical, 4)
        .background((physical / 6) % 2 == 0 ? boardDark : boardLight)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? gold : (isMovable ? turquoise : .clear), lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            guard isMovable else { return }
            handleTap(activeRelative)
        }
    }

    private func checkerBadge(count: Int, color: Color) -> some View {
        ZStack {
            Circle().fill(color).frame(width: 22, height: 22)
                .overlay(Circle().stroke(gold.opacity(0.6), lineWidth: 1))
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color == sand ? night : sand)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if multiplayer == nil || localColor == .white {
                Button {
                    resetGame()
                } label: {
                    Label(t("New Game", "Новая игра"), systemImage: "arrow.counterclockwise")
                }
            }
            Spacer()
            if let mp = multiplayer {
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

    private func handleTap(_ relative: Int) {
        guard multiplayer != nil else {
            engine.moveFrom(relative)
            return
        }
        if localColor == .white {
            engine.humanMove(relative, color: .white)
            sendCurrentDeal()
        } else {
            multiplayer?.send(NetMessage(moveRelative: relative))
        }
    }

    private func botTurnIfNeeded() {
        guard multiplayer == nil else { return }
        guard engine.turn == .black, engine.winner == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            engine.playBotTurnIfNeeded()
        }
    }

    private func resetGame() {
        if multiplayer != nil {
            guard localColor == .white else { return }
            engine.reset()
            sendCurrentDeal()
        } else {
            engine.reset()
        }
    }

    private func sendCurrentDeal() {
        let deal = DealPayload(
            whitePoints: engine.points[.white] ?? [],
            blackPoints: engine.points[.black] ?? [],
            whiteBorneOff: engine.borneOff[.white] ?? 0,
            blackBorneOff: engine.borneOff[.black] ?? 0,
            turn: engine.turn,
            dice: engine.dice,
            lastRoll: engine.lastRoll,
            winner: engine.winner
        )
        multiplayer?.send(NetMessage(deal: deal))
    }

    private func setupMultiplayerReceiver() {
        guard let mp = multiplayer else { return }
        if localColor == .white {
            // Host already rolled the real opening dice in engine's init(); broadcast
            // it so the guest mirrors the exact same board/turn/dice instead of
            // generating its own random roll.
            sendCurrentDeal()
        }
        mp.onReceive = { data in
            guard let msg = try? JSONDecoder().decode(NetMessage.self, from: data) else { return }
            DispatchQueue.main.async {
                if let deal = msg.deal {
                    engine.applyDeal(
                        whitePoints: deal.whitePoints,
                        blackPoints: deal.blackPoints,
                        whiteBorneOff: deal.whiteBorneOff,
                        blackBorneOff: deal.blackBorneOff,
                        turn: deal.turn,
                        dice: deal.dice,
                        lastRoll: deal.lastRoll,
                        winner: deal.winner
                    )
                } else if let relative = msg.moveRelative, localColor == .white {
                    // Host applies a move request from the guest (always black),
                    // then rebroadcasts the resulting authoritative state.
                    engine.humanMove(relative, color: .black)
                    sendCurrentDeal()
                }
            }
        }
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
    GameView(store: StoreManager())
}
