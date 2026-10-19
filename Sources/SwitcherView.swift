import SwiftUI

private var neon: Color { Settings.shared.theme.color }
private var neonDim: Color { Settings.shared.theme.dimColor }
private var accent: Color { Settings.shared.theme.accent }
private var glitchA: Color { Settings.shared.theme.glitchColors.1 }
private var glitchB: Color { Settings.shared.theme.glitchColors.0 }

private extension View {
    func neonGlow(_ color: Color = neon, radius: CGFloat = 6) -> some View {
        shadow(color: color.opacity(0.9), radius: radius * 0.4)
            .shadow(color: color.opacity(0.7), radius: radius)
            .shadow(color: color.opacity(0.4), radius: radius * 2.2)
    }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @ObservedObject var settings = Settings.shared

    static let size: CGFloat = 700
    static let iconRadius: CGFloat = 208
    private let size = SwitcherView.size
    private let diskDiameter: CGFloat = 640
    private let iconRadius = SwitcherView.iconRadius

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !settings.animations)) { timeline in
            let t = settings.animations ? timeline.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                backdrop(t)
                tickRing
                rotatingRings(t)
                selectionBeam
                icons
                center(t)
                hudLabels(t)
            }
            .frame(width: size, height: size)
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: model.cursor)
        .scaleEffect(settings.size.scale)
        .frame(width: size * settings.size.scale, height: size * settings.size.scale)
    }

    // MARK: - Geometry

    private var count: Int { max(model.items.count, 1) }

    private func angle(for index: Int) -> Angle {
        .radians(Double(index) / Double(count) * 2 * .pi - .pi / 2)
    }

    private func position(for index: Int, radius: CGFloat) -> CGPoint {
        let a = angle(for: index).radians
        return CGPoint(x: size / 2 + radius * cos(a), y: size / 2 + radius * sin(a))
    }

    private var iconSize: CGFloat {
        let slot = 2 * .pi * iconRadius / CGFloat(count)
        return min(max(slot * 0.6, 30), 68)
    }

    // MARK: - Layers

    private func backdrop(_ t: Double) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [neon.opacity(0.22), .clear],
                                     center: .center, startRadius: diskDiameter * 0.42, endRadius: size / 2))
            Circle()
                .fill(RadialGradient(colors: [settings.theme.backgroundInner, settings.theme.backgroundOuter],
                                     center: .center, startRadius: 0, endRadius: diskDiameter / 2))
                .opacity(0.95)
                .frame(width: diskDiameter, height: diskDiameter)
            // Theme pattern + scanlines
            Canvas { ctx, sz in
                Self.drawPattern(settings.theme.pattern, in: &ctx, size: sz, t: t)
                for y in stride(from: 0.0, to: settings.scanlines ? Double(sz.height) : 0, by: 3) {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: sz.width, height: 1)), with: .color(.black.opacity(0.28)))
                }
            }
            .frame(width: diskDiameter, height: diskDiameter)
            .clipShape(Circle())
            Circle()
                .stroke(neon, lineWidth: 2.2)
                .frame(width: diskDiameter, height: diskDiameter)
                .neonGlow(radius: 8)
            Circle()
                .stroke(neonDim.opacity(0.8), lineWidth: 1)
                .frame(width: diskDiameter - 14, height: diskDiameter - 14)
        }
    }

    // MARK: - Theme backdrops

    private static let glyphs = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎ0123456789Z:.=*+")

    private static func hash(_ a: Int, _ b: Int = 0) -> Int {
        var h = UInt64(bitPattern: Int64(a &* 73_856_093 ^ b &* 19_349_663))
        h ^= h >> 13; h = h &* 0x5bd1e995; h ^= h >> 15
        return Int(h & 0x7fff_ffff)
    }

    private static func drawPattern(_ pattern: BackdropPattern, in ctx: inout GraphicsContext, size sz: CGSize, t: Double) {
        let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
        switch pattern {
        case .grid:
            for r in stride(from: 40.0, to: Double(sz.width / 2), by: 40) {
                let p = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.stroke(p, with: .color(neon.opacity(0.06)), lineWidth: 0.6)
            }
            for i in 0..<12 {
                let a = Double(i) / 12 * 2 * .pi
                var p = Path()
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + cos(a) * sz.width / 2, y: c.y + sin(a) * sz.width / 2))
                ctx.stroke(p, with: .color(neon.opacity(0.05)), lineWidth: 0.6)
            }
            // Radar sweep
            let sweep = t.truncatingRemainder(dividingBy: 4) / 4 * 2 * .pi
            var wedge = Path()
            wedge.move(to: c)
            wedge.addArc(center: c, radius: sz.width / 2, startAngle: .radians(sweep - 0.5), endAngle: .radians(sweep), clockwise: false)
            ctx.fill(wedge, with: .color(neon.opacity(0.06)))

        case .rain:
            let step: CGFloat = 20, trail = 11
            for col in 0..<Int(sz.width / step) {
                let speed = 50 + Double(hash(col) % 70)
                let span = Double(sz.height) + Double(trail) * Double(step)
                let head = (t * speed + Double(hash(col, 7) % 600)).truncatingRemainder(dividingBy: span)
                for k in 0..<trail {
                    let y = head - Double(k) * Double(step)
                    guard y > 0, y < Double(sz.height) else { continue }
                    let g = glyphs[hash(col, k + Int(t * 6)) % glyphs.count]
                    let color = k == 0 ? Color.white.opacity(0.55) : neon.opacity(0.32 * (1 - Double(k) / Double(trail)))
                    ctx.draw(Text(String(g)).font(.system(size: 13, design: .monospaced)).foregroundColor(color),
                             at: CGPoint(x: CGFloat(col) * step + step / 2, y: y))
                }
            }

        case .hex:
            let r: CGFloat = 22
            let w = sqrt(3) * r, h = 1.5 * r
            for row in 0...Int(sz.height / h) + 1 {
                for col in 0...Int(sz.width / w) + 1 {
                    let x = CGFloat(col) * w + (row % 2 == 0 ? 0 : w / 2)
                    let y = CGFloat(row) * h
                    var p = Path()
                    for i in 0..<6 {
                        let a = Double(i) / 6 * 2 * .pi + .pi / 6
                        let pt = CGPoint(x: x + cos(a) * (r - 2), y: y + sin(a) * (r - 2))
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                    p.closeSubpath()
                    ctx.stroke(p, with: .color(neon.opacity(0.08)), lineWidth: 0.8)
                    let pulse = sin(t * 1.4 + Double(hash(col, row) % 628) / 100)
                    if pulse > 0.93 { ctx.fill(p, with: .color(accent.opacity((pulse - 0.93) * 2))) }
                }
            }

        case .horizon:
            let horizon = sz.height * 0.56
            // Striped sun sitting on the horizon
            let sunR: CGFloat = 150
            var sun = Path(ellipseIn: CGRect(x: c.x - sunR, y: horizon - sunR, width: sunR * 2, height: sunR * 2))
            sun = sun.intersection(Path(CGRect(x: 0, y: 0, width: sz.width, height: horizon)))
            for i in 0..<6 {
                let gapY = horizon - CGFloat(i) * 16 - 10
                sun = sun.subtracting(Path(CGRect(x: 0, y: gapY, width: sz.width, height: CGFloat(6 - i))))
            }
            ctx.fill(sun, with: .linearGradient(Gradient(colors: [accent.opacity(0.35), neon.opacity(0.35)]),
                                                startPoint: CGPoint(x: c.x, y: horizon - sunR), endPoint: CGPoint(x: c.x, y: horizon)))
            var line = Path()
            line.move(to: CGPoint(x: 0, y: horizon)); line.addLine(to: CGPoint(x: sz.width, y: horizon))
            ctx.stroke(line, with: .color(neon.opacity(0.6)), lineWidth: 1.5)
            // Scrolling perspective floor
            let rows = 12
            let phase = t.truncatingRemainder(dividingBy: 1)
            for k in 0..<rows {
                let f = (Double(k) + phase) / Double(rows)
                let y = horizon + (sz.height - horizon) * CGFloat(f * f)
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: sz.width, y: y))
                ctx.stroke(p, with: .color(neon.opacity(0.08 + 0.25 * f)), lineWidth: 1)
            }
            for i in -12...12 {
                var p = Path()
                p.move(to: CGPoint(x: c.x + CGFloat(i) * 8, y: horizon))
                p.addLine(to: CGPoint(x: c.x + CGFloat(i) * 70, y: sz.height))
                ctx.stroke(p, with: .color(neon.opacity(0.2)), lineWidth: 1)
            }
        }
    }

    private var tickRing: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let outer = diskDiameter / 2 - 6
            for i in 0..<120 {
                let a = Double(i) / 120 * 2 * .pi
                let major = i % 10 == 0
                let inner = outer - (major ? 9 : 4)
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
                p.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
                ctx.stroke(p, with: .color(neon.opacity(major ? 0.9 : 0.35)), lineWidth: major ? 1.6 : 0.8)
            }
        }
        .frame(width: size, height: size)
    }

    private func rotatingRings(_ t: Double) -> some View {
        ZStack {
            Circle()
                .stroke(neon.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [2, 9]))
                .frame(width: iconRadius * 2 + 70, height: iconRadius * 2 + 70)
                .rotationEffect(.degrees(t * 8))
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .trim(from: 0, to: 0.12)
                    .stroke(accent.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                    .frame(width: iconRadius * 2 - 70, height: iconRadius * 2 - 70)
                    .rotationEffect(.degrees(Double(i) * 120 - t * 22))
                    .neonGlow(accent, radius: 4)
            }
            Circle()
                .stroke(neon.opacity(0.25), style: StrokeStyle(lineWidth: 6, dash: [1, 3]))
                .frame(width: iconRadius * 2 - 90, height: iconRadius * 2 - 90)
                .rotationEffect(.degrees(t * -5))
        }
    }

    private var selectionBeam: some View {
        let sel = model.cursor // unwrapped, so wrap-around keeps rotating forward
        let slice = 1.0 / Double(count)
        return ZStack {
            // Highlighted sector arc behind the selected icon
            Circle()
                .trim(from: 0, to: slice * 0.9)
                .stroke(neon, style: StrokeStyle(lineWidth: iconSize + 22, lineCap: .butt))
                .opacity(0.10)
                .frame(width: iconRadius * 2, height: iconRadius * 2)
                .rotationEffect(angle(for: sel) - .radians(slice * 0.45 * 2 * .pi))
            Circle()
                .trim(from: 0, to: slice * 0.9)
                .stroke(neon, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: iconRadius * 2 + iconSize + 22, height: iconRadius * 2 + iconSize + 22)
                .rotationEffect(angle(for: sel) - .radians(slice * 0.45 * 2 * .pi))
                .neonGlow(radius: 5)
            // Laser from core to target
            Path { p in
                p.move(to: position(for: sel, radius: 112))
                p.addLine(to: position(for: sel, radius: iconRadius - iconSize * 0.75))
            }
            .stroke(accent, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .neonGlow(accent, radius: 4)
        }
        .frame(width: size, height: size)
    }

    private var icons: some View {
        ZStack {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                let selected = index == model.selected
                ZStack {
                    if selected {
                        Circle()
                            .fill(neon.opacity(0.12))
                            .frame(width: iconSize * 1.35, height: iconSize * 1.35)
                        Circle()
                            .stroke(neon, lineWidth: 2)
                            .frame(width: iconSize * 1.35, height: iconSize * 1.35)
                            .neonGlow(radius: 7)
                    }
                    Image(nsImage: item.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: iconSize, height: iconSize)
                        .saturation(selected ? 1 : 0.35)
                        .opacity(selected ? 1 : 0.6)
                        .shadow(color: selected ? neon.opacity(0.6) : .clear, radius: 10)
                    if item.app.isHidden {
                        Circle().fill(accent).frame(width: 5, height: 5)
                            .offset(y: iconSize * 0.62)
                            .neonGlow(radius: 3)
                    }
                }
                .scaleEffect(selected ? 1.22 : 1)
                .position(position(for: index, radius: iconRadius))
            }
        }
        .frame(width: size, height: size)
    }

    private func center(_ t: Double) -> some View {
        let item = model.items.indices.contains(model.selected) ? model.items[model.selected] : nil
        let name = (item?.name ?? "NO SIGNAL").uppercased()
        // Occasional glitch jitter on the title
        let glitchOn = settings.glitch && settings.animations && sin(t * 3.1) > 0.93 || settings.glitch && settings.animations && sin(t * 7.7 + 1) > 0.97
        let jitter: CGFloat = glitchOn ? CGFloat(sin(t * 90)) * 3 : 0

        return ZStack {
            Circle()
                .fill(Color.black.opacity(0.75))
                .frame(width: 210, height: 210)
            Circle()
                .stroke(neon, lineWidth: 1.5)
                .frame(width: 210, height: 210)
                .neonGlow(radius: 6)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(accent.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 192, height: 192)
                .rotationEffect(.degrees(t * 40))

            VStack(spacing: 8) {
                if let item {
                    Image(nsImage: item.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 84, height: 84)
                        .shadow(color: neon.opacity(0.7), radius: 14)
                        .id(item.id)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                ZStack {
                    Text(name).foregroundColor(glitchA.opacity(glitchOn ? 0.8 : 0)).offset(x: -2 + jitter, y: 0)
                    Text(name).foregroundColor(glitchB.opacity(glitchOn ? 0.8 : 0)).offset(x: 2 - jitter, y: 0)
                    Text(name).foregroundColor(neon).neonGlow(radius: 5).offset(x: jitter * 0.5)
                }
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 168)
                Text(String(format: "[%02d/%02d]  PID %d", model.selected + 1, model.items.count, item?.id ?? 0))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(accent.opacity(0.75))
            }
        }
    }

    private func hudLabels(_ t: Double) -> some View {
        let blink = Int(t * 2) % 2 == 0
        return ZStack {
            Text(settings.theme.tagline + (blink ? "_" : " "))
                .offset(y: -diskDiameter / 2 + 34)
            Text("⌘⇥ CYCLE · ESC ABORT · Q KILL · H HIDE")
                .offset(y: diskDiameter / 2 - 34)
            Text("SYS::ONLINE")
                .rotationEffect(.degrees(-90))
                .offset(x: -diskDiameter / 2 + 34)
            Text(String(format: "LINK %03d", model.items.count))
                .rotationEffect(.degrees(90))
                .offset(x: diskDiameter / 2 - 34)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .foregroundColor(accent.opacity(0.8))
        .neonGlow(accent, radius: 2)
    }
}
