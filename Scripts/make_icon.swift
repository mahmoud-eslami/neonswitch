// Renders the NeonSwitch app icon to a 1024x1024 PNG.
// Usage: swift Scripts/make_icon.swift <output.png>
import AppKit
import SwiftUI

let neon = Color(red: 0.22, green: 1.0, blue: 0.08)

extension View {
    func glow(_ r: CGFloat) -> some View {
        shadow(color: neon.opacity(0.9), radius: r * 0.4)
            .shadow(color: neon.opacity(0.7), radius: r)
            .shadow(color: neon.opacity(0.4), radius: r * 2.2)
    }
}

struct Icon: View {
    let canvas: CGFloat = 1024
    let tile: CGFloat = 824          // macOS icon grid: 100px margin
    let slots = 8
    let selected = 1
    let ring: CGFloat = 255

    func point(_ i: Int, _ r: CGFloat) -> CGPoint {
        let a = Double(i) / Double(slots) * 2 * .pi - .pi / 2
        return CGPoint(x: canvas / 2 + r * cos(a), y: canvas / 2 + r * sin(a))
    }

    var body: some View {
        ZStack {
            // Tile
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(RadialGradient(colors: [Color(red: 0.03, green: 0.13, blue: 0.05), .black],
                                     center: .center, startRadius: 0, endRadius: tile * 0.7))
                .frame(width: tile, height: tile)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
            // Grid + scanlines
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                for i in 0..<12 {
                    let a = Double(i) / 12 * 2 * .pi
                    var p = Path(); p.move(to: c)
                    p.addLine(to: CGPoint(x: c.x + cos(a) * sz.width, y: c.y + sin(a) * sz.width))
                    ctx.stroke(p, with: .color(neon.opacity(0.07)), lineWidth: 2)
                }
                for y in stride(from: 0.0, to: Double(sz.height), by: 8) {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: sz.width, height: 3)), with: .color(.black.opacity(0.3)))
                }
            }
            .frame(width: tile, height: tile)
            .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .stroke(neon.opacity(0.35), lineWidth: 4)
                .frame(width: tile - 8, height: tile - 8)

            // Outer ring + ticks
            Circle().stroke(neon, lineWidth: 10)
                .frame(width: 680, height: 680).glow(14)
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                for i in 0..<60 {
                    let a = Double(i) / 60 * 2 * .pi
                    let major = i % 5 == 0
                    let o: CGFloat = 318, inner = o - (major ? 26 : 12)
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
                    p.addLine(to: CGPoint(x: c.x + cos(a) * o, y: c.y + sin(a) * o))
                    ctx.stroke(p, with: .color(neon.opacity(major ? 0.9 : 0.4)), lineWidth: major ? 5 : 3)
                }
            }
            .frame(width: canvas, height: canvas)

            // Rotating-style arc segments
            ForEach(0..<3, id: \.self) { i in
                Circle().trim(from: 0, to: 0.13)
                    .stroke(neon.opacity(0.85), style: StrokeStyle(lineWidth: 12, lineCap: .butt))
                    .frame(width: 330, height: 330)
                    .rotationEffect(.degrees(Double(i) * 120 + 20))
                    .glow(8)
            }

            // Laser to selection
            Path { p in
                p.move(to: point(selected, 110))
                p.addLine(to: point(selected, ring - 62))
            }
            .stroke(neon, style: StrokeStyle(lineWidth: 6, dash: [18, 12]))
            .glow(6)

            // App slots
            ForEach(0..<slots, id: \.self) { i in
                let sel = i == selected
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(sel ? neon.opacity(0.9) : neon.opacity(0.12))
                        .frame(width: sel ? 96 : 70, height: sel ? 96 : 70)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(neon.opacity(sel ? 1 : 0.6), lineWidth: sel ? 0 : 4)
                        .frame(width: 70, height: 70)
                    if sel {
                        Circle().stroke(neon, lineWidth: 7)
                            .frame(width: 140, height: 140).glow(12)
                    }
                }
                .glow(sel ? 14 : 3)
                .position(point(i, ring))
            }
            .frame(width: canvas, height: canvas)

            // Core
            Circle().fill(Color.black.opacity(0.85)).frame(width: 190, height: 190)
            Circle().stroke(neon, lineWidth: 7).frame(width: 190, height: 190).glow(10)
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 92, weight: .bold))
                .foregroundColor(neon)
                .glow(10)
        }
        .frame(width: canvas, height: canvas)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
