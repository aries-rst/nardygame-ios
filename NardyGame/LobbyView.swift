import SwiftUI
import MultipeerConnectivity

struct MultiplayerLobbyView: View {
    @ObservedObject var store: StoreManager
    @ObservedObject private var lang = AppLang.shared
    @StateObject private var multiplayer = MultiplayerManager(serviceType: "ar-nardy")
    @State private var myColor: NardyColor = .white
    @State private var startGame = false
    @Environment(\.dismiss) private var dismiss

    private let night = Color(red: 0.05, green: 0.16, blue: 0.20)
    private let gold = Color(red: 0.85, green: 0.62, blue: 0.22)
    private let sand = Color(red: 0.95, green: 0.90, blue: 0.78)

    var body: some View {
        NavigationStack {
            ZStack {
                night.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "wifi")
                        .font(.system(size: 40))
                        .foregroundStyle(gold)
                        .padding(.top, 20)

                    Text(t("Play Online", "Игра по сети"))
                        .font(.title2.bold())
                        .foregroundStyle(sand)

                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(sand.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if multiplayer.role == .none {
                        VStack(spacing: 14) {
                            Button {
                                myColor = .white
                                multiplayer.startHosting()
                            } label: {
                                lobbyButtonLabel(t("Create Game", "Создать игру"), system: "antenna.radiowaves.left.and.right")
                            }
                            Button {
                                myColor = .black
                                multiplayer.startBrowsing()
                            } label: {
                                lobbyButtonLabel(t("Find Nearby Game", "Найти игру рядом"), system: "magnifyingglass")
                            }
                        }
                        .padding(.horizontal, 32)
                    }

                    if multiplayer.role == .guest {
                        List(multiplayer.availablePeers, id: \.self) { peer in
                            Button {
                                multiplayer.invite(peer)
                            } label: {
                                HStack {
                                    Image(systemName: "iphone")
                                    Text(peer.displayName)
                                    Spacer()
                                    Text(t("Invite", "Пригласить")).font(.caption)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .frame(maxHeight: 240)
                        .scrollContentBackground(.hidden)
                    }

                    if multiplayer.role != .none {
                        Button(t("Cancel", "Отмена")) {
                            multiplayer.stop()
                        }
                        .font(.footnote)
                        .foregroundStyle(sand.opacity(0.6))
                    }

                    if let err = multiplayer.errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }

                    Spacer()
                }
                .padding(.bottom, 24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Close", "Закрыть")) {
                        multiplayer.stop()
                        dismiss()
                    }
                }
            }
            .navigationDestination(isPresented: $startGame) {
                GameView(store: store, multiplayer: multiplayer, localColor: myColor)
            }
            .onChange(of: multiplayer.state) { state in
                if case .connected = state {
                    startGame = true
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func lobbyButtonLabel(_ text: String, system: String) -> some View {
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
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(gold.opacity(0.5), lineWidth: 1))
        )
    }

    private var statusText: String {
        switch multiplayer.state {
        case .idle:
            return t("Create a game so a nearby opponent can find you, or find a game that's already been created. Wi-Fi or Bluetooth required.", "Создайте игру, чтобы вас нашёл соперник рядом, либо найдите уже созданную игру. Нужны Wi-Fi или Bluetooth.")
        case .hosting:
            return t("Waiting for opponent… The other player should open this game and tap \"Find Nearby Game\".", "Ожидание соперника… Другой игрок должен открыть эту игру и нажать «Найти игру рядом».")
        case .browsing:
            return multiplayer.availablePeers.isEmpty ? t("Searching for nearby games…", "Поиск игр рядом…") : t("Choose a game from the list.", "Выберите игру из списка.")
        case .connecting:
            return t("Connecting…", "Подключение…")
        case .connected(let name):
            return t("Connected to \(name). Starting game…", "Подключено к \(name). Начинаем игру…")
        }
    }
}
