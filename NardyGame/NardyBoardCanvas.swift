import SwiftUI

// MARK: - Board snapshot

/// One physical board point (0...23), already collapsed from each seat's
/// own-path indices by the caller (via `NEngine.pathOf`), so this view never
/// needs to know about variant-specific path mapping.
struct NardyPointStack {
    var n0: Int = 0
    var n1: Int = 0
    var pin0: Bool = false
    var pin1: Bool = false
}

/// Everything `NardyBoardCanvas` needs to draw one frame — built by the
/// caller (see the `NardyGameController`/`DailyPuzzleController` extensions
/// below) so this view stays decoupled from `NEngine`'s variant-specific
/// rules (hit/pin/same-direction/cube).
struct NardyBoardSnapshot {
    var points: [NardyPointStack]   // always 24
    var bar0: Int = 0
    var bar1: Int = 0
    var off0: Int = 0
    var off1: Int = 0
    var mySeat: Int = 0
    var movablePoints: Set<Int> = []
    var movableBar: Bool = false
    var showCube: Bool = false
    var cube: Int = 1
    var cubeOwner: Int = -1
    var sameDirection: Bool = true   // cfg.same — picks which side black's bear-off tray sits on
    var hintPoint: Int? = nil        // daily puzzle only
}

/// Classic triangular board — a SwiftUI `Canvas` port of the per-frame parts
/// of Android's `BoardView.kt` `drawBoard()`. This port's controllers resolve
/// a tap on a legal point directly (`tapPoint`/`onBoardTap`, no two-step
/// select-then-target flow) and carry no move/roll animation state, so this
/// view mirrors that: it draws the authentic board art plus the current
/// checker/bar/cube/tray state, and reports taps as a physical point
/// (0...23) or the bar. Dice stay in their existing row above the board
/// rather than being drawn onto it, since nothing here animates a roll yet.
struct NardyBoardCanvas: View {
    var snapshot: NardyBoardSnapshot
    var theme: String
    var onTapPoint: (Int) -> Void
    var onTapBar: () -> Void = {}

    private var pal: NBoardPal { NardyThemes.board(theme) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let scale: CGFloat = (w > 0 && h > 0) ? min(w / NardyBoardGeo.W, h / NardyBoardGeo.H) : 1
            let ox = (w - NardyBoardGeo.W * scale) / 2
            let oy = (h - NardyBoardGeo.H * scale) / 2
            let snap = snapshot
            let p = pal
            Canvas { context, _ in
                context.translateBy(x: ox, y: oy)
                context.scaleBy(x: scale, y: scale)
                NardyBoardBg.paint(context, pal: p)
                NardyBoardCanvas.drawDynamic(&context, snap: snap, pal: p)
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    guard scale > 0 else { return }
                    let bx = (value.location.x - ox) / scale
                    let by = (value.location.y - oy) / scale
                    NardyBoardCanvas.handleTap(bx: bx, by: by, onTapPoint: onTapPoint, onTapBar: onTapBar)
                }
            )
        }
    }

    private static func handleTap(bx: CGFloat, by: CGFloat, onTapPoint: (Int) -> Void, onTapBar: () -> Void) {
        guard bx >= 0, by >= 0, bx <= NardyBoardGeo.W, by <= NardyBoardGeo.H else { return }
        if bx >= 518 && bx <= 562 { onTapBar(); return }
        let top = by < NardyBoardGeo.H / 2
        for b in 0..<24 {
            if NardyBoardGeo.isTop(b) != top { continue }
            let x = NardyBoardGeo.x(b)
            if bx >= x - NardyBoardGeo.CW / 2 && bx <= x + NardyBoardGeo.CW / 2 {
                onTapPoint(b)
                return
            }
        }
    }

    // MARK: - Dynamic layer (checkers, bar, cube, trays, highlights)

    private static func drawDynamic(_ ctx: inout GraphicsContext, snap: NardyBoardSnapshot, pal: NBoardPal) {
        typealias B = NardyBoardGeo
        for b in 0..<24 {
            let st = snap.points[b]
            if st.n0 == 0 && st.n1 == 0 { continue }
            var order: [(p: Int, cnt: Int, pinned: Bool)] = []
            if st.n0 > 0 && st.n1 > 0 {
                let under = st.pin0 ? 0 : 1
                order.append((under, 1, true))
                order.append((1 - under, under == 0 ? st.n1 : st.n0, false))
            } else if st.n0 > 0 {
                order.append((0, st.n0, false))
            } else {
                order.append((1, st.n1, false))
            }
            let total = st.n0 + st.n1
            let step = B.stepFor(total)
            let top = B.isTop(b)
            let x = B.x(b)
            var k = 0
            var topP = -1
            for (p, cnt, pinned) in order {
                for _ in 0..<cnt {
                    let y = B.stackY(top: top, k: k, step: step)
                    drawChecker(&ctx, x: x, y: y, p: p, pal: pal)
                    if pinned { drawRing(&ctx, x: x, y: y, color: Color(hex: 0xFFDD3333), width: 3, dashed: true) }
                    k += 1
                }
                topP = p
            }
            let ty = B.stackY(top: top, k: total - 1, step: step)
            if total > 6 {
                drawLabel(&ctx, x: x, y: ty, text: "\(total)", size: 22,
                          color: topP == 0 ? Color(hex: 0xFF3A2A10) : Color(hex: 0xFFF4E6C8))
            }
            if snap.movablePoints.contains(b) {
                drawRing(&ctx, x: x, y: ty, color: pal.hl, width: 3.5, dashed: true)
            }
            if snap.hintPoint == b {
                drawRing(&ctx, x: x, y: ty, color: .yellow, width: 4, dashed: false)
            }
        }
        // bar checkers (hitting games only — n/a for long nardy/fevga)
        for p in 0...1 {
            let count = p == 0 ? snap.bar0 : snap.bar1
            guard count > 0 else { continue }
            let cy: CGFloat = p == 0 ? B.H / 2 + 70 : B.H / 2 - 70
            drawChecker(&ctx, x: 540, y: cy, p: p, pal: pal)
            if count > 1 {
                drawLabel(&ctx, x: 540, y: cy, text: "\(count)", size: 20,
                          color: p == 0 ? Color(hex: 0xFF3A2A10) : Color(hex: 0xFFF4E6C8))
            }
            if p == snap.mySeat && snap.movableBar {
                drawRing(&ctx, x: 540, y: cy, color: pal.hl, width: 5, dashed: false)
            }
        }
        // doubling cube
        if snap.showCube {
            let cy: CGFloat = snap.cubeOwner == 0 ? B.H - 46 : (snap.cubeOwner == 1 ? 46 : B.H / 2)
            let rect = CGRect(x: 516, y: cy - 24, width: 48, height: 48)
            let cp = RoundedRectangle(cornerRadius: 8).path(in: rect)
            ctx.fill(cp, with: .color(Color(hex: 0xFFF7F1E3)))
            ctx.stroke(cp, with: .color(Color(hex: 0xFF555555)), lineWidth: 2)
            let value = snap.cube == 1 ? 64 : snap.cube
            drawLabel(&ctx, x: 540, y: cy, text: "\(value)", size: 22, color: Color(hex: 0xFF222222))
        }
        // bear-off trays: white bottom-right; black top-right (opposite
        // direction) or top-left (same direction, e.g. long nardy/fevga)
        let trays: [(p: Int, x: CGFloat, top: Bool)] = [
            (0, 1024, false),
            (1, snap.sameDirection ? 6 : 1024, true),
        ]
        for tr in trays {
            let shown = tr.p == 0 ? snap.off0 : snap.off1
            guard shown > 0 else { continue }
            let fillColor = tr.p == 0 ? pal.w2 : pal.b2
            let strokeColor = tr.p == 0 ? pal.w3 : pal.b3
            for k in 0..<shown {
                let y: CGFloat = tr.top ? 20 + CGFloat(k) * 14 : B.H - 32 - CGFloat(k) * 14
                let r = CGRect(x: tr.x + 5, y: y, width: 40, height: 12)
                let rp = RoundedRectangle(cornerRadius: 4).path(in: r)
                ctx.fill(rp, with: .color(fillColor))
                ctx.stroke(rp, with: .color(strokeColor), lineWidth: 1)
            }
        }
    }

    private static func drawChecker(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, p: Int, pal: NBoardPal) {
        let c1 = p == 0 ? pal.w1 : pal.b1
        let c2 = p == 0 ? pal.w2 : pal.b2
        let c3 = p == 0 ? pal.w3 : pal.b3
        let r = NardyBoardGeo.R - 1
        let shadow = Path(ellipseIn: CGRect(x: x - r + 1.5, y: y - r + 2.5, width: r * 2, height: r * 2))
        ctx.fill(shadow, with: .color(Color.black.opacity(0.28)))
        let circle = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        ctx.fill(circle, with: .radialGradient(Gradient(colors: [c1, c2, c3]),
                                                center: CGPoint(x: x - r * 0.24, y: y - r * 0.36),
                                                startRadius: 0, endRadius: r * 1.44))
        ctx.stroke(circle, with: .color(c3), lineWidth: 1.5)
        let ir = NardyBoardGeo.R - 9
        let inner = Path(ellipseIn: CGRect(x: x - ir, y: y - ir, width: ir * 2, height: ir * 2))
        let ringColor = pal.ring != nil ? pal.ring!.opacity(0.9) : c3.opacity(0.45)
        ctx.stroke(inner, with: .color(ringColor), lineWidth: 2)
    }

    private static func drawRing(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, color: Color, width: CGFloat, dashed: Bool) {
        let r = NardyBoardGeo.R + 3
        let p = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dashed ? [7, 5] : []))
    }

    private static func drawLabel(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, text: String, size: CGFloat, color: Color) {
        let label = Text(text).font(.system(size: size, weight: .bold)).foregroundColor(color)
        ctx.draw(label, at: CGPoint(x: x, y: y), anchor: .center)
    }
}

// MARK: - Snapshot builders

extension NardyGameController {
    /// Collapses `state` into board-point-indexed counts for `NardyBoardCanvas`.
    var boardSnapshot: NardyBoardSnapshot {
        var points = [NardyPointStack](repeating: NardyPointStack(), count: 24)
        for b in 0..<24 {
            let i0 = NEngine.pathOf(variant, 0, b)
            let i1 = NEngine.pathOf(variant, 1, b)
            points[b] = NardyPointStack(n0: state.pos[0][i0], n1: state.pos[1][i1],
                                         pin0: state.pin[0][i0] != 0, pin1: state.pin[1][i1] != 0)
        }
        let mv = movable(seat: localSeat)
        let cfg = NEngine.cfg(variant)
        return NardyBoardSnapshot(
            points: points, bar0: state.bar[0], bar1: state.bar[1],
            off0: state.off[0], off1: state.off[1], mySeat: localSeat,
            movablePoints: mv.points, movableBar: mv.bar,
            showCube: cfg.cube, cube: state.cube, cubeOwner: state.cubeOwner,
            sameDirection: cfg.same, hintPoint: nil
        )
    }
}

extension DailyPuzzleController {
    /// Long Nardy only, solo, no bar/cube — a much smaller snapshot than the
    /// full game's.
    var boardSnapshot: NardyBoardSnapshot {
        var points = [NardyPointStack](repeating: NardyPointStack(), count: 24)
        for b in 0..<24 {
            let i0 = NEngine.pathOf(.long, 0, b)
            points[b] = NardyPointStack(n0: state.pos[0][i0], n1: 0, pin0: false, pin1: false)
        }
        return NardyBoardSnapshot(
            points: points, bar0: 0, bar1: 0, off0: state.off[0], off1: 0,
            mySeat: 0, movablePoints: movablePoints, movableBar: false,
            showCube: false, cube: 1, cubeOwner: -1, sameDirection: true,
            hintPoint: hintFrom
        )
    }
}

// MARK: - Theme selection (Android has a dedicated Settings screen for this;
// this port keeps it to a single shared, persisted choice, picked from a
// sheet off `GameView`).

final class NardyBoardTheme: ObservableObject {
    static let shared = NardyBoardTheme()
    @Published var id: String {
        didSet { UserDefaults.standard.set(id, forKey: "nardyBoardTheme") }
    }
    private init() {
        id = UserDefaults.standard.string(forKey: "nardyBoardTheme") ?? "wood"
    }
}

struct NardyThemePickerView: View {
    @ObservedObject private var theme = NardyBoardTheme.shared
    @ObservedObject private var lang = AppLang.shared
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(NardyThemes.ids, id: \.self) { id in
                        swatch(id)
                    }
                }
                .padding(16)
            }
            .navigationTitle(t("Board Theme", "Тема доски"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Close", "Закрыть")) { dismiss() }
                }
            }
        }
    }

    private func swatch(_ id: String) -> some View {
        let pal = NardyThemes.board(id)
        let selected = theme.id == id
        return Button {
            theme.id = id
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(pal.felt)
                    .frame(height: 54)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(pal.frame, lineWidth: 4))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .padding(4)
                        }
                    }
                Text(NardyThemes.displayName(id))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
