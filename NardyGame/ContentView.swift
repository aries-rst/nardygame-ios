import SwiftUI

// Silk Road palette — warm ochre, copper, turquoise accent.
// Distinct from Checkers (dark wood/brass/felt), Domino (poster primaries)
// and Durak (burgundy/gold).
enum SilkRoadPalette {
    static let sand = Color(red: 0.82, green: 0.65, blue: 0.42)
    static let copper = Color(red: 0.72, green: 0.40, blue: 0.20)
    static let turquoise = Color(red: 0.15, green: 0.55, blue: 0.55)
    static let night = Color(red: 0.10, green: 0.07, blue: 0.09)
}

struct ContentView: View {
    var body: some View {
        ZStack {
            SilkRoadPalette.night.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("НАРДЫ")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(SilkRoadPalette.copper)
                Text("Шёлковый путь")
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(SilkRoadPalette.turquoise)
                Text("5 региональных вариантов · Честность костей")
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(SilkRoadPalette.sand.opacity(0.8))
                RoundedRectangle(cornerRadius: 12)
                    .fill(SilkRoadPalette.sand.opacity(0.15))
                    .frame(width: 220, height: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(SilkRoadPalette.copper, lineWidth: 3)
                    )
                    .overlay(Text("Board scaffold").foregroundStyle(SilkRoadPalette.sand.opacity(0.5)))
            }
        }
    }
}

#Preview {
    ContentView()
}
