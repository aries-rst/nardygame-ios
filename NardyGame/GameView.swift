import SwiftUI

struct GameView: View {
    @ObservedObject var store: StoreManager
    @StateObject private var engine = NardyEngine()
    @Environment(\.dismiss) private var dismiss

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
        .onAppear { botTurnIfNeeded() }
        .alert("Игра окончена", isPresented: Binding(get: { engine.winner != nil }, set: { _ in })) {
            Button("Новая игра") { engine.reset() }
            Button("В меню") { dismiss() }
        } message: {
            Text(engine.winner == .white ? "Вы победили!" : "Бот победил!")
        }
    }

    private var header: some View {
        HStack {
            Text("Белые вне: \(engine.borneOff[.white] ?? 0)/15")
                .foregroundStyle(sand)
            Spacer()
            Text(engine.turn == .white ? "Ваш ход" : "Ход бота")
                .font(.headline)
                .foregroundStyle(gold)
            Spacer()
            Text("Чёрные вне: \(engine.borneOff[.black] ?? 0)/15")
                .foregroundStyle(sand)
        }
        .font(.caption)
        .padding(.horizontal, 16)
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
        let isMovable = engine.turn == .white && engine.movablePoints(for: .white).contains(physical)
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
            engine.moveFrom(physical)
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
            Button {
                engine.reset()
            } label: {
                Label("Новая игра", systemImage: "arrow.counterclockwise")
            }
            Spacer()
            if !store.isPremium {
                Text("Реклама в бесплатной версии")
                    .font(.caption)
                    .foregroundStyle(sand.opacity(0.5))
            }
        }
        .foregroundStyle(sand)
        .padding(.horizontal, 18)
    }

    private func botTurnIfNeeded() {
        guard engine.turn == .black, engine.winner == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            engine.playBotTurnIfNeeded()
        }
    }
}

struct PremiumView: View {
    @ObservedObject var store: StoreManager
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
                    featureRow("Без рекламы")
                    featureRow("Локальный мультиплеер по Wi-Fi/Bluetooth")
                    featureRow("Разовая покупка — навсегда")
                }
                .padding(.horizontal, 24)

                if store.isPremium {
                    Label("Premium уже активен", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task { await store.purchasePremium() }
                    } label: {
                        Text("Купить за \(store.priceText)")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(gold)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)

                    Button("Восстановить покупки") {
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
                    Button("Закрыть") { dismiss() }
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
