import SwiftUI

struct NardyOptions: Codable {
    var variant: NVariant = .long
    var botLevel: Int = 1

    private static let key = "nardy.options.v2"
    static func load() -> NardyOptions {
        guard let data = UserDefaults.standard.data(forKey: key),
              let o = try? JSONDecoder().decode(NardyOptions.self, from: data) else {
            return NardyOptions()
        }
        return o
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

func nardyVariantName(_ v: NVariant) -> String {
    switch v {
    case .long: return t("Long Nardy", "Длинные нарды")
    case .short: return t("Backgammon", "Короткие нарды")
    case .tavla: return t("Tavla", "Тавла")
    case .plakoto: return t("Plakoto", "Плакото")
    case .fevga: return t("Fevga", "Февга")
    }
}

struct ContentView: View {
    @StateObject private var store = StoreManager()
    @ObservedObject private var lang = AppLang.shared
    @State private var options = NardyOptions.load()
    @State private var showGame = false
    @State private var showPremium = false
    @State private var showLobby = false
    @State private var showStats = false
    @State private var showDailyPuzzle = false

    private let night = Color(red: 0.05, green: 0.16, blue: 0.20)
    private let gold = Color(red: 0.85, green: 0.62, blue: 0.22)
    private let turquoise = Color(red: 0.17, green: 0.56, blue: 0.55)
    private let sand = Color(red: 0.95, green: 0.90, blue: 0.78)
    private let olive = Color(red: 0.14, green: 0.30, blue: 0.29)

    var body: some View {
        NavigationStack {
            ZStack {
                night.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        languageToggle

                        header

                        variantGrid

                        Text(variantHelp)
                            .font(.caption)
                            .foregroundStyle(sand.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        difficultySection

                        VStack(spacing: 14) {
                            Button {
                                options.save()
                                showGame = true
                            } label: {
                                menuLabel(t("Play vs Bot", "Играть с ботом"), system: "dice.fill")
                            }

                            Button {
                                if store.isPremium {
                                    showLobby = true
                                } else {
                                    showPremium = true
                                }
                            } label: {
                                menuLabel(t("Play Online (Wi-Fi/Bluetooth)", "Игра по сети (Wi-Fi/Bluetooth)"), system: "wifi")
                            }

                            Button {
                                showPremium = true
                            } label: {
                                menuLabel(store.isPremium ? t("Premium Active", "Premium активен") : t("Premium — \(store.priceText)", "Premium — \(store.priceText)"), system: store.isPremium ? "crown.fill" : "crown")
                            }
                        }

                        HStack(spacing: 14) {
                            Button {
                                showDailyPuzzle = true
                            } label: {
                                secondaryLabel(t("Puzzle of the Day", "Задача дня"), system: "calendar")
                            }
                            Button {
                                showStats = true
                            } label: {
                                secondaryLabel(t("Stats", "Статистика"), system: "chart.bar.fill")
                            }
                        }

                        CrossPromoSection(accent: gold, textColor: sand, cardFill: turquoise.opacity(0.18))

                        Text(store.isPremium ? t("Ads disabled · Local multiplayer unlocked", "Реклама отключена · Локальный мультиплеер открыт") : t("Free version · with ads", "Бесплатная версия · с рекламой"))
                            .font(.footnote)
                            .foregroundStyle(sand.opacity(0.6))
                    }
                    .padding(20)
                }
            }
            .navigationDestination(isPresented: $showGame) {
                GameView(store: store, variant: options.variant, botLevel: options.botLevel)
            }
            .navigationDestination(isPresented: $showLobby) {
                MultiplayerLobbyView(store: store, variant: options.variant)
            }
            .sheet(isPresented: $showPremium) {
                PremiumView(store: store)
            }
            .sheet(isPresented: $showStats) {
                NardyStatsView()
            }
            .sheet(isPresented: $showDailyPuzzle) {
                DailyPuzzleView()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var languageToggle: some View {
        HStack {
            Spacer()
            Button {
                AppLang.shared.isRussian.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    Text(lang.isRussian ? "EN" : "RU").fontWeight(.semibold)
                }
                .font(.caption)
                .foregroundStyle(sand)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    Capsule().fill(turquoise.opacity(0.18))
                        .overlay(Capsule().stroke(gold.opacity(0.5), lineWidth: 1))
                )
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 46))
                .foregroundStyle(gold)
            Text("SILK ROAD")
                .font(.system(size: 28, weight: .heavy, design: .serif))
                .foregroundStyle(sand)
                .tracking(3)
            Text(t("5 rulesets · dice, cube & bear-off", "5 вариантов · кости, куб и вывод шашек"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(turquoise)
                .multilineTextAlignment(.center)
        }
    }

    private var variantGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(NEngine.VARIANTS, id: \.self) { v in
                variantButton(v)
            }
        }
    }

    private func variantButton(_ v: NVariant) -> some View {
        let selected = options.variant == v
        return Button {
            options.variant = v
        } label: {
            Text(nardyVariantName(v))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(sand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(selected ? turquoise.opacity(0.4) : olive.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selected ? gold : sand.opacity(0.15), lineWidth: selected ? 2 : 1)
                        )
                )
        }
    }

    private var variantHelp: String {
        switch options.variant {
        case .long:
            return t("Both players move the same direction around the board. No hitting — any point may hold both colors. 6-in-a-row prime illegal unless an opponent is ahead of it.", "Оба игрока ходят в одну сторону. Без боя — на любом пункте могут стоять шашки обоих цветов. 6 подряд занятых пунктов запрещены, если впереди нет шашки соперника.")
        case .short:
            return t("Classic backgammon: opposite directions, hitting sends a blot to the bar, doubling cube included.", "Классические короткие нарды: ходы в разные стороны, бой отправляет шашку на бар, есть куб удвоения.")
        case .tavla:
            return t("Turkish backgammon: hitting, but a die that can bear a checker off may not be wasted on a smaller move, and a checker that hits can't move again that turn.", "Турецкая тавла: бой есть, но кость, которой можно вывести шашку, нельзя потратить на меньший ход; ударившая шашка не ходит повторно в этот ход.")
        case .plakoto:
            return t("A lone blot gets pinned in place (not sent to the bar) until the pinning checker moves away. Pinning the opponent's head checker wins double at once.", "Одинокая шашка не идёт на бар, а запирается на месте — пока запирающая шашка не уйдёт. Запереть шашку на старте соперника — немедленная двойная победа.")
        case .fevga:
            return t("Both players move the same direction from adjacent corners. No hitting. Only your lead checker may move until it passes the opponent's start.", "Оба игрока ходят в одну сторону из соседних углов. Без боя. Ходит только головная шашка, пока не пройдёт старт соперника.")
        }
    }

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(t("DIFFICULTY", "СЛОЖНОСТЬ"))
            HStack(spacing: 12) {
                chip(t("Easy", "Лёгкий"), selected: options.botLevel == 0) { options.botLevel = 0 }
                chip(t("Medium", "Средний"), selected: options.botLevel == 1) { options.botLevel = 1 }
                chip(t("Hard", "Сложный"), selected: options.botLevel == 2) { options.botLevel = 2 }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(sand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selected ? turquoise.opacity(0.4) : olive.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selected ? gold : sand.opacity(0.12), lineWidth: selected ? 2 : 1)
                        )
                )
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(sand.opacity(0.55))
            .tracking(1.2)
    }

    private func menuLabel(_ text: String, system: String) -> some View {
        HStack {
            Image(systemName: system)
            Text(text).fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.right").font(.caption)
        }
        .foregroundStyle(sand)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(turquoise.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(gold.opacity(0.5), lineWidth: 1))
        )
    }

    private func secondaryLabel(_ text: String, system: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: system).font(.title3)
            Text(text).font(.caption.bold())
        }
        .foregroundStyle(sand)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(sand.opacity(0.15), lineWidth: 1))
        )
    }
}

#Preview {
    ContentView()
}
