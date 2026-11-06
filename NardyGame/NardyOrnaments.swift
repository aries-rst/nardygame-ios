import SwiftUI

// MARK: - Small helpers that make porting Android's `Canvas`/`Path` code
// (which issues relative moves like `rLineTo`/`rQuadTo`, and uses explicit
// save()/restore() for transforms) read almost line-for-line in Swift.
// `GraphicsContext` is a value type, so copying it into a local `var` and
// mutating the copy is already the save/restore pattern — no explicit
// restore calls are needed below.

extension Path {
    mutating func moveRel(_ dx: CGFloat, _ dy: CGFloat) {
        let p = currentPoint ?? .zero
        move(to: CGPoint(x: p.x + dx, y: p.y + dy))
    }
    mutating func lineRel(_ dx: CGFloat, _ dy: CGFloat) {
        let p = currentPoint ?? .zero
        addLine(to: CGPoint(x: p.x + dx, y: p.y + dy))
    }
    mutating func quadRel(_ cdx: CGFloat, _ cdy: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
        let p = currentPoint ?? .zero
        addQuadCurve(to: CGPoint(x: p.x + dx, y: p.y + dy), control: CGPoint(x: p.x + cdx, y: p.y + cdy))
    }
    mutating func cubicRel(_ c1dx: CGFloat, _ c1dy: CGFloat, _ c2dx: CGFloat, _ c2dy: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
        let p = currentPoint ?? .zero
        addCurve(to: CGPoint(x: p.x + dx, y: p.y + dy), control1: CGPoint(x: p.x + c1dx, y: p.y + c1dy), control2: CGPoint(x: p.x + c2dx, y: p.y + c2dy))
    }
}

extension GraphicsContext {
    mutating func rotate(byDegrees degrees: Double, around px: CGFloat, _ py: CGFloat) {
        translateBy(x: px, y: py)
        rotate(by: .degrees(degrees))
        translateBy(x: -px, y: -py)
    }
    mutating func scale(_ sx: CGFloat, _ sy: CGFloat, around px: CGFloat, _ py: CGFloat) {
        translateBy(x: px, y: py)
        scaleBy(x: sx, y: sy)
        translateBy(x: -px, y: -py)
    }
}

/// Board centre motifs (one per felt half) — a port of Android's `Ornaments.kt`.
/// Geometry is translated path-for-path from the Kotlin source; a handful of
/// cosmetic touches (the carved relief's drop-shadow layer, the khokhloma
/// leaf arcs) are approximated rather than pixel-identical, since this is a
/// different 2D drawing API (SwiftUI `GraphicsContext` vs. Android `Canvas`)
/// with no simulator available here to compare renders side-by-side.
enum NardyOrnaments {
    static func star8(_ cx: CGFloat, _ cy: CGFloat, _ r1: CGFloat, _ r2: CGFloat) -> Path {
        var p = Path()
        for i in 0..<16 {
            let a = Double.pi * Double(i) / 8
            let r = (i % 2 == 1) ? r2 : r1
            let x = cx + r * CGFloat(cos(a))
            let y = cy + r * CGFloat(sin(a))
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }

    private static let carved: Set<String> = ["dragon", "arabesque", "knot", "islimi"]

    static func draw(_ context: GraphicsContext, pal: NBoardPal, cx: CGFloat, cy: CGFloat, mirror: Bool) {
        let style = pal.ornStyle
        if style == "none" { return }
        var ctx = context
        if mirror && pal.mirrorDecor {
            ctx.scale(-1, 1, around: cx, cy)
        }
        if carved.contains(style) {
            // relief: light edge up-left, shadow down-right, then the ink
            var light = ctx
            light.translateBy(x: -1.6, y: -1.6)
            motif(&light, pal: pal, style: style, cx: cx, cy: cy, col: Color(hex: 0xFFFFF6E0).opacity(0.35), relief: true)
            var shadow = ctx
            shadow.translateBy(x: 2, y: 2)
            motif(&shadow, pal: pal, style: style, cx: cx, cy: cy, col: Color.black.opacity(0.40), relief: true)
            motif(&ctx, pal: pal, style: style, cx: cx, cy: cy, col: pal.orn.opacity(pal.ornAlpha), relief: false)
        } else {
            motif(&ctx, pal: pal, style: style, cx: cx, cy: cy, col: pal.orn.opacity(pal.ornAlpha), relief: false)
        }
    }

    /// relief = true draws only the silhouette (no inner felt-colored details).
    private static func motif(_ ctx: inout GraphicsContext, pal: NBoardPal, style: String, cx: CGFloat, cy: CGFloat, col: Color, relief: Bool) {
        switch style {
        case "dragon": drawDragon(&ctx, pal: pal, cx: cx, cy: cy, col: col, relief: relief)
        case "arabesque": drawArabesque(&ctx, cx: cx, cy: cy, col: col)
        case "knot": drawKnot(&ctx, cx: cx, cy: cy, col: col)
        case "islimi": drawIslimi(&ctx, pal: pal, cx: cx, cy: cy, col: col, relief: relief)
        case "rhombus": drawRhombus(&ctx, cx: cx, cy: cy)
        case "rosette": drawRosette(&ctx, cx: cx, cy: cy, col: col)
        case "starMed": drawStarMed(&ctx, cx: cx, cy: cy)
        case "suzani": drawSuzani(&ctx, pal: pal, cx: cx, cy: cy, col: col)
        case "tulip": drawTulip(&ctx, cx: cx, cy: cy, col: col)
        case "meander": drawMeander(&ctx, cx: cx, cy: cy, col: col)
        case "medallion": drawMedallion(&ctx, pal: pal, cx: cx, cy: cy, col: col)
        case "khokhloma": drawKhokhloma(&ctx, pal: pal, cx: cx, cy: cy, col: col)
        default: drawStar(&ctx, cx: cx, cy: cy, col: col) // girih rosette
        }
    }

    // MARK: dragon (carved)

    private static func drawDragon(_ ctx: inout GraphicsContext, pal: NBoardPal, cx: CGFloat, cy: CGFloat, col: Color, relief: Bool) {
        var body = Path()
        body.move(to: CGPoint(x: cx - 150, y: cy + 70))
        body.addCurve(to: CGPoint(x: cx + 20, y: cy + 10), control1: CGPoint(x: cx - 120, y: cy - 40), control2: CGPoint(x: cx - 40, y: cy + 90))
        body.addCurve(to: CGPoint(x: cx + 150, y: cy - 30), control1: CGPoint(x: cx + 80, y: cy - 70), control2: CGPoint(x: cx + 120, y: cy - 70))
        ctx.stroke(body, with: .color(col), style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))
        if !relief {
            ctx.stroke(body, with: .color(pal.felt.opacity(0.8)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round, dash: [3, 9]))
        }
        var tail = Path()
        tail.move(to: CGPoint(x: cx - 150, y: cy + 70))
        tail.quadRel(-30, 25, -10, 50)
        tail.quadRel(20, 18, 34, -6)
        ctx.stroke(tail, with: .color(col), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        var head = Path()
        head.move(to: CGPoint(x: cx + 150, y: cy - 30))
        head.lineRel(34, -18); head.lineRel(-6, 22); head.lineRel(26, 6); head.lineRel(-30, 14)
        head.closeSubpath()
        ctx.fill(head, with: .color(col))
        ctx.stroke(head, with: .color(col), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        if !relief {
            ctx.fill(Path(ellipseIn: CGRect(x: cx + 168 - 4, y: cy - 34 - 4, width: 8, height: 8)), with: .color(pal.felt))
        }
        var whisker1 = Path()
        whisker1.move(to: CGPoint(x: cx + 176, y: cy - 46))
        whisker1.quadRel(14, -30, -4, -50)
        ctx.stroke(whisker1, with: .color(col), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        var whisker2 = Path()
        whisker2.move(to: CGPoint(x: cx + 188, y: cy - 38))
        whisker2.quadRel(22, -20, 14, -46)
        ctx.stroke(whisker2, with: .color(col), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        var wing1 = Path()
        wing1.move(to: CGPoint(x: cx - 30, y: cy + 40))
        wing1.lineRel(-40, -110); wing1.lineRel(30, 30); wing1.lineRel(10, -50); wing1.lineRel(22, 46); wing1.lineRel(22, -40); wing1.lineRel(6, 60)
        wing1.closeSubpath()
        ctx.fill(wing1, with: .color(col.opacity(0.85)))
        var wing2 = Path()
        wing2.move(to: CGPoint(x: cx + 60, y: cy - 10))
        wing2.lineRel(20, -90); wing2.lineRel(18, 30); wing2.lineRel(22, -44); wing2.lineRel(8, 64)
        wing2.closeSubpath()
        ctx.fill(wing2, with: .color(col.opacity(0.75)))
        var spines = Path()
        spines.move(to: CGPoint(x: cx - 80, y: cy + 55)); spines.lineRel(-10, 30)
        spines.move(to: CGPoint(x: cx - 80 + 40, y: cy + 55 - 18)); spines.lineRel(-6, 30)
        spines.move(to: CGPoint(x: cx - 80 + 40 + 92, y: cy + 55 - 18 - 60)); spines.lineRel(4, 30)
        spines.move(to: CGPoint(x: cx - 80 + 40 + 92 + 40, y: cy + 55 - 18 - 60 - 60)); spines.lineRel(8, 28)
        ctx.stroke(spines, with: .color(col), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
    }

    // MARK: arabesque (carved)

    private static func drawArabesque(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, col: Color) {
        for k in 0..<4 {
            var g = ctx
            g.rotate(byDegrees: Double(k) * 90, around: cx, cy)
            var tendril = Path()
            tendril.move(to: CGPoint(x: cx, y: cy - 26))
            tendril.addCurve(to: CGPoint(x: cx + 80, y: cy - 40), control1: CGPoint(x: cx + 10, y: cy - 70), control2: CGPoint(x: cx + 70, y: cy - 80))
            tendril.addCurve(to: CGPoint(x: cx + 36, y: cy - 22), control1: CGPoint(x: cx + 90, y: cy), control2: CGPoint(x: cx + 50, y: cy + 6))
            tendril.addCurve(to: CGPoint(x: cx + 62, y: cy - 30), control1: CGPoint(x: cx + 22, y: cy - 50), control2: CGPoint(x: cx + 56, y: cy - 42))
            g.stroke(tendril, with: .color(col), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            var leaf1 = g
            leaf1.rotate(byDegrees: -25, around: cx + 20, cy - 92)
            leaf1.fill(Path(ellipseIn: CGRect(x: cx + 11, y: cy - 114, width: 18, height: 44)), with: .color(col))
            var leaf2 = g
            leaf2.rotate(byDegrees: 50, around: cx + 96, cy - 64)
            leaf2.fill(Path(ellipseIn: CGRect(x: cx + 88, y: cy - 82, width: 16, height: 36)), with: .color(col))
            g.fill(Path(ellipseIn: CGRect(x: cx + 62 - 5, y: cy - 30 - 5, width: 10, height: 10)), with: .color(col))
        }
        var center = ctx
        center.stroke(Path(ellipseIn: CGRect(x: cx - 24, y: cy - 24, width: 48, height: 48)), with: .color(col), style: StrokeStyle(lineWidth: 5))
        center.fill(star8(cx, cy, 16, 7), with: .color(col))
    }

    // MARK: knot (carved)

    private static func drawKnot(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, col: Color) {
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - 96, y: cy - 96, width: 192, height: 192)), with: .color(col), style: StrokeStyle(lineWidth: 10))
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - 80, y: cy - 80, width: 160, height: 160)), with: .color(col), style: StrokeStyle(lineWidth: 4))
        for (dx, dy) in [(-34.0, 0.0), (34.0, 0.0), (0.0, -34.0), (0.0, 34.0)] {
            ctx.stroke(Path(ellipseIn: CGRect(x: cx + dx - 44, y: cy + dy - 44, width: 88, height: 88)), with: .color(col), style: StrokeStyle(lineWidth: 10))
        }
        var g = ctx
        g.rotate(byDegrees: 45, around: cx, cy)
        g.stroke(Path(CGRect(x: cx - 40, y: cy - 40, width: 80, height: 80)), with: .color(col), style: StrokeStyle(lineWidth: 6, lineJoin: .miter))
    }

    // MARK: islimi (carved)

    private static func drawIslimi(_ ctx: inout GraphicsContext, pal: NBoardPal, cx: CGFloat, cy: CGFloat, col: Color, relief: Bool) {
        for i in 0..<8 {
            var g = ctx
            g.rotate(byDegrees: Double(i) * 45, around: cx, cy)
            var petal = Path()
            petal.move(to: CGPoint(x: cx, y: cy - 30))
            petal.addCurve(to: CGPoint(x: cx, y: cy - 118), control1: CGPoint(x: cx - 26, y: cy - 60), control2: CGPoint(x: cx - 20, y: cy - 104))
            petal.addCurve(to: CGPoint(x: cx, y: cy - 30), control1: CGPoint(x: cx + 20, y: cy - 104), control2: CGPoint(x: cx + 26, y: cy - 60))
            petal.closeSubpath()
            g.fill(petal, with: .color(col))
            if !relief {
                g.fill(Path(ellipseIn: CGRect(x: cx - 7, y: cy - 74 - 7, width: 14, height: 14)), with: .color(pal.felt))
            }
        }
        var ring = Path()
        for i in 0..<24 {
            let a = Double.pi * Double(i) / 12
            let px = cx + 132 * CGFloat(cos(a)); let py = cy + 132 * CGFloat(sin(a))
            ring.addEllipse(in: CGRect(x: px - 7, y: py - 7, width: 14, height: 14))
        }
        ctx.fill(ring, with: .color(col))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 28, y: cy - 28, width: 56, height: 56)), with: .color(col))
        if !relief {
            ctx.fill(star8(cx, cy, 20, 9), with: .color(pal.felt))
        }
    }

    // MARK: rhombus (mahogany inlay — layered diamonds, no carve relief)

    private static func drawRhombus(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat) {
        let layers: [(CGFloat, UInt32)] = [(118, 0xFFEFDCB4), (96, 0xFF5A1E10), (76, 0xFFC98A4A), (56, 0xFF1A0F0A), (38, 0xFFEFDCB4), (20, 0xFF8E3B22)]
        for (r, c) in layers {
            var p = Path()
            p.move(to: CGPoint(x: cx, y: cy - r * 1.35))
            p.addLine(to: CGPoint(x: cx + r, y: cy))
            p.addLine(to: CGPoint(x: cx, y: cy + r * 1.35))
            p.addLine(to: CGPoint(x: cx - r, y: cy))
            p.closeSubpath()
            ctx.fill(p, with: .color(Color(hex: c)))
        }
    }

    // MARK: rosette (walnut / ebony inlay)

    private static func drawRosette(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, col: Color) {
        for i in 0..<16 {
            var g = ctx
            g.rotate(byDegrees: Double(i) * 22.5, around: cx, cy)
            g.stroke(Path(ellipseIn: CGRect(x: cx - 10, y: cy - 92, width: 20, height: 68)), with: .color(col), style: StrokeStyle(lineWidth: 2.5))
        }
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - 104, y: cy - 104, width: 208, height: 208)), with: .color(col), style: StrokeStyle(lineWidth: 2))
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - 112, y: cy - 112, width: 224, height: 224)), with: .color(col), style: StrokeStyle(lineWidth: 1))
        ctx.fill(star8(cx, cy, 26, 11), with: .color(col))
    }

    // MARK: starMed (khatam marquetry star)

    private static func drawStarMed(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat) {
        let layers: [(CGFloat, CGFloat, UInt32)] = [(104, 54, 0xFF2A1A10), (90, 46, 0xFFEFE2C4), (66, 34, 0xFF2F7A5A), (44, 22, 0xFFB3271C), (24, 12, 0xFFEFE2C4)]
        for (r1, r2, c) in layers {
            ctx.fill(star8(cx, cy, r1, r2), with: .color(Color(hex: c)))
        }
    }

    // MARK: suzani (embroidered rosette)

    private static func drawSuzani(_ ctx: inout GraphicsContext, pal: NBoardPal, cx: CGFloat, cy: CGFloat, col: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 34, y: cy - 34, width: 68, height: 68)), with: .color(col))
        for i in 0..<8 {
            var g = ctx
            g.rotate(byDegrees: Double(i) * 45, around: cx, cy)
            g.fill(Path(ellipseIn: CGRect(x: cx - 12, y: cy - 84, width: 24, height: 40)), with: .color(col))
        }
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - 98, y: cy - 98, width: 196, height: 196)), with: .color(col), style: StrokeStyle(lineWidth: 4, dash: [10, 6]))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 13, y: cy - 13, width: 26, height: 26)), with: .color(pal.felt.opacity(0.95)))
    }

    // MARK: tulip (Iznik tile motif)

    private static func drawTulip(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, col: Color) {
        func tulip(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat) {
            var stem = Path()
            stem.move(to: CGPoint(x: x, y: y + 44 * k))
            stem.addLine(to: CGPoint(x: x, y: y - 6 * k))
            ctx.stroke(stem, with: .color(col), style: StrokeStyle(lineWidth: 4 * k, lineCap: .round))
            var leafL = ctx
            leafL.rotate(byDegrees: -35, around: x, y + 30 * k)
            leafL.fill(Path(ellipseIn: CGRect(x: x - 26 * k, y: y + 24 * k, width: 26 * k, height: 12 * k)), with: .color(col))
            var leafR = ctx
            leafR.rotate(byDegrees: 35, around: x, y + 30 * k)
            leafR.fill(Path(ellipseIn: CGRect(x: x, y: y + 24 * k, width: 26 * k, height: 12 * k)), with: .color(col))
            var bloom = Path()
            bloom.move(to: CGPoint(x: x - 18 * k, y: y))
            bloom.addQuadCurve(to: CGPoint(x: x - 9 * k, y: y - 46 * k), control: CGPoint(x: x - 24 * k, y: y - 30 * k))
            bloom.addLine(to: CGPoint(x: x, y: y - 30 * k))
            bloom.addLine(to: CGPoint(x: x + 9 * k, y: y - 46 * k))
            bloom.addQuadCurve(to: CGPoint(x: x + 18 * k, y: y), control: CGPoint(x: x + 24 * k, y: y - 30 * k))
            bloom.closeSubpath()
            ctx.fill(bloom, with: .color(col))
        }
        tulip(cx, cy, 1); tulip(cx - 120, cy + 4, 0.75); tulip(cx + 120, cy + 4, 0.75)
    }

    // MARK: meander (Aegean key band)

    private static func drawMeander(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, col: Color) {
        var rails = Path()
        rails.move(to: CGPoint(x: cx - 212, y: cy - 20)); rails.addLine(to: CGPoint(x: cx + 212, y: cy - 20))
        rails.move(to: CGPoint(x: cx - 212, y: cy + 20)); rails.addLine(to: CGPoint(x: cx + 212, y: cy + 20))
        ctx.stroke(rails, with: .color(col), style: StrokeStyle(lineWidth: 3.5, lineCap: .butt))
        var x0 = cx - 208
        var key = Path()
        while x0 + 30 <= cx + 210 {
            key.move(to: CGPoint(x: x0, y: cy + 13))
            key.addLine(to: CGPoint(x: x0, y: cy - 13))
            key.addLine(to: CGPoint(x: x0 + 22, y: cy - 13))
            key.addLine(to: CGPoint(x: x0 + 22, y: cy + 6))
            key.addLine(to: CGPoint(x: x0 + 8, y: cy + 6))
            key.addLine(to: CGPoint(x: x0 + 8, y: cy - 5))
            key.addLine(to: CGPoint(x: x0 + 14, y: cy - 5))
            key.move(to: CGPoint(x: x0, y: cy + 13))
            key.addLine(to: CGPoint(x: x0 + 30, y: cy + 13))
            x0 += 30
        }
        ctx.stroke(key, with: .color(col), style: StrokeStyle(lineWidth: 3.5, lineCap: .butt))
    }

    // MARK: medallion (Caucasian carpet diamond)

    private static func drawMedallion(_ ctx: inout GraphicsContext, pal: NBoardPal, cx: CGFloat, cy: CGFloat, col: Color) {
        func diaPath(_ r1: CGFloat, _ r2: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: cx, y: cy - r1))
            p.addLine(to: CGPoint(x: cx + r2, y: cy))
            p.addLine(to: CGPoint(x: cx, y: cy + r1))
            p.addLine(to: CGPoint(x: cx - r2, y: cy))
            p.closeSubpath()
            return p
        }
        ctx.fill(diaPath(112, 92), with: .color(col))
        ctx.fill(diaPath(70, 58), with: .color(pal.felt))
        ctx.fill(diaPath(34, 28), with: .color(col))
        var hooks = Path()
        for sx: CGFloat in [-1, 1] {
            hooks.move(to: CGPoint(x: cx + sx * 92, y: cy)); hooks.addLine(to: CGPoint(x: cx + sx * 128, y: cy))
            hooks.move(to: CGPoint(x: cx + sx * 128, y: cy)); hooks.addLine(to: CGPoint(x: cx + sx * 128, y: cy - 18 * sx))
            hooks.move(to: CGPoint(x: cx + sx * 150, y: cy - 14)); hooks.addLine(to: CGPoint(x: cx + sx * 150, y: cy + 14))
        }
        ctx.stroke(hooks, with: .color(col), style: StrokeStyle(lineWidth: 5))
    }

    // MARK: khokhloma (lacquerware berries and curls)

    private static func drawKhokhloma(_ ctx: inout GraphicsContext, pal: NBoardPal, cx: CGFloat, cy: CGFloat, col: Color) {
        var curls = Path()
        curls.addArc(center: CGPoint(x: cx - 95, y: cy), radius: 55, startAngle: .degrees(300), endAngle: .degrees(580), clockwise: false)
        curls.addArc(center: CGPoint(x: cx + 95, y: cy), radius: 55, startAngle: .degrees(240), endAngle: .degrees(-40), clockwise: true)
        ctx.stroke(curls, with: .color(col), style: StrokeStyle(lineWidth: 4))
        for i in 0..<8 {
            var g = ctx
            g.rotate(byDegrees: Double(i) * 45 + 22, around: cx, cy)
            g.fill(Path(ellipseIn: CGRect(x: cx - 9, y: cy - 66, width: 18, height: 36)), with: .color(col))
        }
        var berries = Path()
        for i in 0..<5 {
            let a = (Double(i) * 72 - 90) * .pi / 180
            let px = cx + 17 * CGFloat(cos(a)); let py = cy + 17 * CGFloat(sin(a))
            berries.addEllipse(in: CGRect(x: px - 11, y: py - 11, width: 22, height: 22))
        }
        ctx.fill(berries, with: .color(pal.ptA.opacity(0.95)))
        var sheen = Path()
        for i in 0..<5 {
            let a = (Double(i) * 72 - 90) * .pi / 180
            let px = cx + 17 * CGFloat(cos(a)) - 3; let py = cy + 17 * CGFloat(sin(a)) - 3
            sheen.addEllipse(in: CGRect(x: px - 3, y: py - 3, width: 6, height: 6))
        }
        ctx.fill(sheen, with: .color(Color.white.opacity(0.5)))
    }

    // MARK: star (default — girih rosette)

    private static func drawStar(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, col: Color) {
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - 78, y: cy - 78, width: 156, height: 156)), with: .color(col), style: StrokeStyle(lineWidth: 3))
        ctx.stroke(star8(cx, cy, 70, 31.5), with: .color(col), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - 19.6, y: cy - 19.6, width: 39.2, height: 39.2)), with: .color(col), style: StrokeStyle(lineWidth: 3))
    }
}
