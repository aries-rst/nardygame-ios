import SwiftUI

/// Classic horizontal board geometry — 1:1 port of Android's `BoardGeo` object
/// in BoardView.kt. White path 0..23 runs along the top row right→left, then
/// the bottom row left→right (counter-clockwise); white home is the
/// bottom-right quadrant; bear-off trays sit on the sides. All coordinates
/// are in "board space" (0...W, 0...H); `NardyBoardCanvas` maps that to the
/// actual view size.
enum NardyBoardGeo {
    static let W: CGFloat = 1080
    static let H: CGFloat = 640
    static let R: CGFloat = 30       // checker radius
    static let PL: CGFloat = 265     // point length
    static let CW: CGFloat = 440 / 6 // point column width
    static let LX: CGFloat = 70      // left half inner-x
    static let RX: CGFloat = 570     // right half inner-x

    static func colX(_ c: Int) -> CGFloat { c < 6 ? LX + CW * (CGFloat(c) + 0.5) : RX + CW * (CGFloat(c - 6) + 0.5) }
    static func isTop(_ b: Int) -> Bool { b <= 11 }
    static func col(_ b: Int) -> Int { b <= 11 ? 11 - b : b - 12 }
    static func x(_ b: Int) -> CGFloat { colX(col(b)) }
    static func stepFor(_ n: Int) -> CGFloat { n <= 1 ? 0 : min(2 * R, (PL - 2 * R) / CGFloat(n - 1)) }
    static func stackY(top: Bool, k: Int, step: CGFloat) -> CGFloat { top ? 20 + R + CGFloat(k) * step : H - 20 - R - CGFloat(k) * step }

    /// Deterministic wood-grain strokes, generated once (seeded, matching Android's `java.util.Random(11)` in *spirit* — not bit-identical, since the two platforms' PRNGs differ, but same visual effect: short wavy strokes scattered over the board).
    static let grain: [Path] = {
        var rng = NSeededRandom(seed: 11)
        var paths: [Path] = []
        paths.reserveCapacity(260)
        for _ in 0..<260 {
            var p = Path()
            let y0 = rng.nextFloat() * H
            let amp = 2 + rng.nextFloat() * 6
            let len = 120 + rng.nextFloat() * 520
            let x0 = rng.nextFloat() * W - 60
            p.move(to: CGPoint(x: x0, y: y0))
            var xx = x0
            while xx < x0 + len {
                let nx = xx + 40
                let sign: CGFloat = rng.nextBool() ? 1 : -1
                p.addQuadCurve(to: CGPoint(x: nx, y: y0 + (rng.nextFloat() - 0.5) * amp), control: CGPoint(x: xx + 20, y: y0 + sign * amp))
                xx = nx
            }
            paths.append(p)
        }
        return paths
    }()
}

/// Minimal deterministic PRNG (xorshift32) so `NardyBoardGeo.grain` is stable
/// across redraws without depending on `SystemRandomNumberGenerator`.
struct NSeededRandom {
    private var state: UInt32
    init(seed: UInt32) { state = seed == 0 ? 0xA5A5A5A5 : seed }
    private mutating func next() -> UInt32 {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5
        return state
    }
    mutating func nextFloat() -> CGFloat { CGFloat(next() % 1_000_000) / 1_000_000 }
    mutating func nextBool() -> Bool { next() % 2 == 0 }
}

private let dicePips: [Int: [(CGFloat, CGFloat)]] = [
    1: [(50, 50)],
    2: [(28, 28), (72, 72)],
    3: [(28, 28), (50, 50), (72, 72)],
    4: [(28, 28), (72, 28), (28, 72), (72, 72)],
    5: [(28, 28), (72, 28), (50, 50), (28, 72), (72, 72)],
    6: [(28, 25), (72, 25), (28, 50), (72, 50), (28, 75), (72, 75)],
]

/// Static board layer (frame, inlays, felt, motifs, points) — a port of
/// Android's `BoardBg.paint`. Draws directly into board-space coordinates;
/// the caller (`NardyBoardCanvas`) is responsible for scaling/translating
/// into actual view pixels via `GraphicsContext`'s transform.
enum NardyBoardBg {
    static func diePips(_ value: Int) -> [(CGFloat, CGFloat)] { dicePips[value] ?? [] }

    private static func grainIn(_ ctx: GraphicsContext, rect: CGRect, alpha: Double) {
        guard alpha > 0 else { return }
        var g = ctx
        g.clip(to: Path(rect))
        let color = Color(hex: 0xFF2A1406).opacity(0.16 * alpha)
        var all = Path()
        for p in NardyBoardGeo.grain { all.addPath(p) }
        g.stroke(all, with: .color(color), style: StrokeStyle(lineWidth: 2.2))
    }

    private static func diamond(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat, _ hw: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x, y: y0))
        p.addLine(to: CGPoint(x: x + hw, y: (y0 + y1) / 2))
        p.addLine(to: CGPoint(x: x, y: y1))
        p.addLine(to: CGPoint(x: x - hw, y: (y0 + y1) / 2))
        p.closeSubpath()
        return p
    }

    static func paint(_ context: GraphicsContext, pal: NBoardPal) {
        let B = NardyBoardGeo
        var ctx = context
        // frame
        let frameRect = RoundedRectangle(cornerRadius: 18).path(in: CGRect(x: 0, y: 0, width: B.W, height: B.H))
        ctx.fill(frameRect, with: .color(pal.frame))
        grainIn(ctx, rect: CGRect(x: 0, y: 0, width: B.W, height: B.H), alpha: pal.grain)
        if pal.khatam {
            var kctx = ctx
            let clip = RoundedRectangle(cornerRadius: 16).path(in: CGRect(x: 4, y: 4, width: B.W - 8, height: B.H - 8))
            kctx.clip(to: clip)
            kctx.fill(Path(CGRect(x: 4, y: 4, width: B.W - 8, height: B.H - 8)), with: .color(Color(hex: 0xFF2A1A10)))
            let s1 = NardyOrnaments.star8(0, 0, 10, 4.2)
            let s2 = NardyOrnaments.star8(0, 0, 5, 2.2)
            var ty: CGFloat = 4
            while ty < B.H {
                var tx: CGFloat = 4
                while tx < B.W {
                    var g = kctx
                    g.translateBy(x: tx, y: ty)
                    g.fill(s1, with: .color(Color(hex: 0xFFEFE2C4)))
                    g.fill(s2, with: .color(Color(hex: 0xFF2F7A5A)))
                    g.fill(Path(ellipseIn: CGRect(x: -3, y: -3, width: 6, height: 6)), with: .color(Color(hex: 0xFFB3271C)))
                    tx += 26
                }
                ty += 26
            }
        }
        if let stitch = pal.stitch {
            ctx.stroke(RoundedRectangle(cornerRadius: 14).path(in: CGRect(x: 9, y: 9, width: B.W - 18, height: B.H - 18)),
                       with: .color(stitch), style: StrokeStyle(lineWidth: 2.5, dash: [9, 6]))
        }
        if let rim = pal.rim {
            ctx.stroke(RoundedRectangle(cornerRadius: 18).path(in: CGRect(x: 3, y: 3, width: B.W - 6, height: B.H - 6)),
                       with: .color(rim), style: StrokeStyle(lineWidth: 3))
        }
        // trays
        let trayColor = pal.frameIn.opacity(pal.trayA)
        ctx.fill(RoundedRectangle(cornerRadius: 8).path(in: CGRect(x: 6, y: 14, width: 50, height: B.H - 28)), with: .color(trayColor))
        ctx.fill(RoundedRectangle(cornerRadius: 8).path(in: CGRect(x: 1024, y: 14, width: 50, height: B.H - 28)), with: .color(trayColor))
        // halves
        let fg = pal.effFeltGrain
        for (i, hx) in [B.LX - 8, B.RX - 8].enumerated() {
            let r = CGRect(x: hx, y: 12, width: 456, height: B.H - 24)
            ctx.fill(RoundedRectangle(cornerRadius: 6).path(in: r), with: .color(pal.felt))
            grainIn(ctx, rect: r, alpha: fg)
            if let border = pal.feltBorder {
                ctx.stroke(RoundedRectangle(cornerRadius: 4).path(in: CGRect(x: hx + 5, y: 17, width: 446, height: B.H - 34)), with: .color(border), style: StrokeStyle(lineWidth: 2))
            }
            var hctx = ctx
            hctx.clip(to: Path(r))
            NardyOrnaments.draw(hctx, pal: pal, cx: hx + 228, cy: B.H / 2, mirror: i == 1)
        }
        // hinge bar
        ctx.fill(Path(CGRect(x: 518, y: 0, width: 44, height: B.H)), with: .color(pal.frame))
        grainIn(ctx, rect: CGRect(x: 518, y: 0, width: 44, height: B.H), alpha: pal.grain)
        for hy: CGFloat in [110, B.H - 150] {
            ctx.fill(RoundedRectangle(cornerRadius: 4).path(in: CGRect(x: 530, y: hy, width: 20, height: 40)), with: .color(pal.hinge))
            ctx.fill(Path(ellipseIn: CGRect(x: 537.5, y: hy + 7.5, width: 5, height: 5)), with: .color(Color.black.opacity(0.4)))
            ctx.fill(Path(ellipseIn: CGRect(x: 537.5, y: hy + 27.5, width: 5, height: 5)), with: .color(Color.black.opacity(0.4)))
        }
        // points
        for b in 0..<24 { point(ctx, pal: pal, b: b) }
    }

    private static func tri(_ x: CGFloat, _ yb: CGFloat, _ w: CGFloat, _ tip: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x - w, y: yb))
        p.addLine(to: CGPoint(x: x + w, y: yb))
        p.addLine(to: CGPoint(x: x, y: tip))
        p.closeSubpath()
        return p
    }

    private static func point(_ context: GraphicsContext, pal: NBoardPal, b: Int) {
        let B = NardyBoardGeo
        let x = B.x(b); let top = B.isTop(b); let c = B.col(b)
        let yb: CGFloat = top ? 12 : B.H - 12
        let yt: CGFloat = top ? 12 + B.PL : B.H - 12 - B.PL
        let dir: CGFloat = top ? 1 : -1
        let col = (c % 2 == 1) ? pal.ptA : pal.ptB
        let other = (c % 2 == 1) ? pal.ptB : pal.ptA
        let hw = B.CW / 2 - 3
        var ctx = context
        switch pal.pointStyle {
        case "inlay":
            let w = hw * 0.72; let tip = yt - dir * 16
            let p = tri(x, yb, w, tip)
            ctx.fill(p, with: .color(col))
            ctx.stroke(p, with: .color(Color.black.opacity(0.35)), style: StrokeStyle(lineWidth: 1.2))
            ctx.fill(diamond(x, tip + dir * 6, tip + dir * 26, 6), with: .color(col))
            ctx.fill(diamond(x, yb + dir * 14, yb + dir * 38, 7), with: .color(other.opacity(0.9)))
        case "outlined":
            let p = tri(x, yb, hw, yt)
            if c % 2 == 1 {
                var hctx = ctx
                hctx.clip(to: p)
                hctx.rotate(byDegrees: 35, around: x, (yb + yt) / 2)
                var lines = Path()
                var lx = x - 200
                while lx < x + 200 {
                    lines.move(to: CGPoint(x: lx, y: (yb + yt) / 2 - 220))
                    lines.addLine(to: CGPoint(x: lx, y: (yb + yt) / 2 + 220))
                    lx += 8
                }
                hctx.stroke(lines, with: .color(pal.burn.opacity(0.55)), style: StrokeStyle(lineWidth: 2))
            }
            ctx.stroke(p, with: .color(pal.burn), style: StrokeStyle(lineWidth: 3.5, lineJoin: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: yt - dir * 22 - 4, width: 8, height: 8)), with: .color(pal.burn))
        case "arrow":
            let p = tri(x, yb, hw, yt)
            ctx.fill(p, with: .color(col))
            ctx.stroke(p, with: .color(Color.black.opacity(0.30)), style: StrokeStyle(lineWidth: 1))
            ctx.fill(diamond(x, yb + dir * 10, yb + dir * 38, 9), with: .color(pal.inlay))
        default:
            let p = tri(x, yb, hw, yt)
            ctx.fill(p, with: .color(col))
            ctx.stroke(p, with: .color(Color.black.opacity(0.28)), style: StrokeStyle(lineWidth: 1))
        }
    }
}
