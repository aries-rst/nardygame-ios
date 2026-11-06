import SwiftUI

/// Dice-fairness and vs-bot win/loss stats — matches Android's StatsScreen.
struct NardyStatsView: View {
    @ObservedObject private var lang = AppLang.shared
    @Environment(\.dismiss) private var dismiss
    @State private var snap = NardyStats.shared.snapshot()

    private let night = Color(red: 0.05, green: 0.16, blue: 0.20)
    private let gold = Color(red: 0.85, green: 0.62, blue: 0.22)
    private let turquoise = Color(red: 0.17, green: 0.56, blue: 0.55)
    private let coral = Color(red: 0.85, green: 0.42, blue: 0.36)
    private let sand = Color(red: 0.95, green: 0.90, blue: 0.78)

    private let faceGlyphs = ["⚀", "⚁", "⚂", "⚃", "⚄", "⚅"]

    private var meTotal: Int { snap.meFaces.reduce(0, +) }
    private var botTotal: Int { snap.botFaces.reduce(0, +) }

    private func pct(_ a: Int, _ total: Int) -> String {
        guard total > 0 else { return "—" }
        return String(format: "%.1f%%", 100.0 * Double(a) / Double(total))
    }

    private func frac(_ a: Int, _ total: Int) -> Double {
        guard total > 0 else { return 0 }
        return 100.0 * Double(a) / Double(total)
    }

    private var maxPct: Double {
        var m = 20.0
        for i in 0..<6 {
            m = max(m, frac(snap.meFaces[i], meTotal))
            m = max(m, frac(snap.botFaces[i], botTotal))
        }
        return m
    }

    var body: some View {
        NavigationStack {
            ZStack {
                night.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("🎲 " + t("Dice Statistics", "Статистика костей"))
                            .font(.title3.bold())
                            .foregroundStyle(sand)

                        HStack {
                            Spacer().frame(width: 36)
                            Text(t("Your rolls", "Ваши броски"))
                                .font(.caption).foregroundStyle(sand.opacity(0.6)).frame(maxWidth: .infinity)
                            Text(t("Bot rolls", "Броски бота"))
                                .font(.caption).foregroundStyle(sand.opacity(0.6)).frame(maxWidth: .infinity)
                        }

                        ForEach(0..<6, id: \.self) { i in
                            HStack(spacing: 8) {
                                Text(faceGlyphs[i])
                                    .font(.title2)
                                    .foregroundStyle(sand)
                                    .frame(width: 36)
                                diceBar(value: snap.meFaces[i], total: meTotal, color: turquoise)
                                diceBar(value: snap.botFaces[i], total: botTotal, color: coral)
                            }
                        }

                        HStack {
                            Text(t("Doubles", "Дубли")).font(.caption).foregroundStyle(sand).frame(width: 90, alignment: .leading)
                            Text(pct(snap.meDbl, snap.meRolls)).font(.caption).foregroundStyle(sand).frame(maxWidth: .infinity)
                            Text(pct(snap.botDbl, snap.botRolls)).font(.caption).foregroundStyle(sand).frame(maxWidth: .infinity)
                        }
                        HStack {
                            Text(t("Rolls", "Броски")).font(.caption).foregroundStyle(sand).frame(width: 90, alignment: .leading)
                            Text("\(snap.meRolls)").font(.caption).foregroundStyle(sand).frame(maxWidth: .infinity)
                            Text("\(snap.botRolls)").font(.caption).foregroundStyle(sand).frame(maxWidth: .infinity)
                        }

                        Text(t("A fair die lands on each face about 16.7% of the time.", "Честная кость выпадает на каждую грань примерно в 16.7% случаев."))
                            .font(.caption2)
                            .foregroundStyle(sand.opacity(0.5))

                        Rectangle().fill(sand.opacity(0.15)).frame(height: 1)

                        Text("🏆 " + t("Results vs Bot", "Результаты против бота"))
                            .font(.title3.bold())
                            .foregroundStyle(sand)

                        HStack {
                            Spacer().frame(width: 100)
                            Text(t("Easy", "Лёгкий")).font(.caption).foregroundStyle(sand.opacity(0.6)).frame(maxWidth: .infinity)
                            Text(t("Medium", "Средний")).font(.caption).foregroundStyle(sand.opacity(0.6)).frame(maxWidth: .infinity)
                            Text(t("Hard", "Сложный")).font(.caption).foregroundStyle(sand.opacity(0.6)).frame(maxWidth: .infinity)
                        }

                        ForEach(NEngine.VARIANTS, id: \.self) { v in
                            HStack {
                                Text(nardyVariantName(v))
                                    .font(.caption).foregroundStyle(sand).frame(width: 100, alignment: .leading)
                                ForEach(0..<3, id: \.self) { level in
                                    let r = NardyStats.shared.result(variant: v, level: level)
                                    Text("\(r.wins):\(r.losses)")
                                        .font(.caption).foregroundStyle(sand).frame(maxWidth: .infinity)
                                }
                            }
                        }

                        Button(role: .destructive) {
                            NardyStats.shared.reset()
                            snap = NardyStats.shared.snapshot()
                        } label: {
                            Text(t("Reset Statistics", "Сбросить статистику"))
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.5), lineWidth: 1))
                        }
                        .padding(.top, 8)
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Close", "Закрыть")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func diceBar(value: Int, total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: max(2, geo.size.width * CGFloat(frac(value, total) / maxPct)), height: 10)
            }
            .frame(height: 10)
            Text(pct(value, total)).font(.caption2).foregroundStyle(sand.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NardyStatsView()
}
