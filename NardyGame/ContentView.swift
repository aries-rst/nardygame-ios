import SwiftUI

struct ContentView: View {
    @StateObject private var store = StoreManager()
    @State private var showGame = false
    @State private var showPremium = false
    @State private var showLobby = false

    private let night = Color(red: 0.05, green: 0.16, blue: 0.20)
    private let gold = Color(red: 0.85, green: 0.62, blue: 0.22)
    private let turquoise = Color(red: 0.17, green: 0.56, blue: 0.55)
    private let sand = Color(red: 0.95, green: 0.90, blue: 0.78)

    var body: some View {
        NavigationStack {
            ZStack {
                night.ignoresSafeArea()
                VStack(spacing: 28) {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(gold)
                        Text("SILK ROAD")
                            .font(.system(size: 30, weight: .heavy, design: .serif))
                            .foregroundStyle(sand)
                            .tracking(3)
                        Text("Длинные нарды")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(turquoise)
                    }

                    VStack(spacing: 14) {
                        Button {
                            showGame = true
                        } label: {
                            menuLabel("Играть с ботом", system: "dice.fill")
                        }

                        Button {
                            if store.isPremium {
                                showLobby = true
                            } else {
                                showPremium = true
                            }
                        } label: {
                            menuLabel("Игра по сети (Wi-Fi/Bluetooth)", system: "wifi")
                        }

                        Button {
                            showPremium = true
                        } label: {
                            menuLabel(store.isPremium ? "Premium активен" : "Premium — \(store.priceText)", system: store.isPremium ? "crown.fill" : "crown")
                        }
                    }
                    .padding(.horizontal, 32)

                    CrossPromoSection(accent: gold, textColor: sand, cardFill: turquoise.opacity(0.18))

                    Spacer()

                    Text(store.isPremium ? "Реклама отключена · Локальный мультиплеер открыт" : "Бесплатная версия · с рекламой")
                        .font(.footnote)
                        .foregroundStyle(sand.opacity(0.6))
                        .padding(.bottom, 24)
            }
            }
            .navigationDestination(isPresented: $showGame) {
                GameView(store: store)
            }
            .navigationDestination(isPresented: $showLobby) {
                MultiplayerLobbyView(store: store)
            }
            .sheet(isPresented: $showPremium) {
                PremiumView(store: store)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func menuLabel(_ text: String, system: String) -> some View {
        HStack {
            Image(systemName: system)
            Text(text)
                .fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
        }
        .foregroundStyle(sand)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(turquoise.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(gold.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

#Preview {
    ContentView()
}
