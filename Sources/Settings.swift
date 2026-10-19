import SwiftUI

typealias RGB = (Double, Double, Double)

enum BackdropPattern {
    case grid, rain, hex, horizon
}

/// A full visual preset: two-tone neon palette, background tint, animated backdrop and HUD tagline.
/// Raw values stay stable so saved preferences keep working.
enum NeonTheme: String, CaseIterable {
    case green, matrix, cyan, magenta, vapor, amber, red, purple, arctic

    var title: String {
        switch self {
        case .green: return "Toxic Green"
        case .matrix: return "Matrix"
        case .cyan: return "Tron Grid"
        case .magenta: return "Synthwave"
        case .vapor: return "Vaporwave"
        case .amber: return "Blade Runner"
        case .red: return "Akira"
        case .purple: return "Ultraviolet"
        case .arctic: return "Arctic Ghost"
        }
    }

    var tagline: String {
        switch self {
        case .green: return "// NEON.SWITCH v1.0"
        case .matrix: return "// WAKE UP, NEO..."
        case .cyan: return "// ENTER THE GRID"
        case .magenta: return "// OUTRUN.1986"
        case .vapor: return "// Ａ Ｅ Ｓ Ｔ Ｈ Ｅ Ｔ Ｉ Ｃ"
        case .amber: return "// TYRELL CORP. NEXUS-6"
        case .red: return "// NEO-TOKYO.2019"
        case .purple: return "// UV.SPECTRUM"
        case .arctic: return "// ICE.BREAKER"
        }
    }

    var pattern: BackdropPattern {
        switch self {
        case .green, .purple: return .grid
        case .matrix, .arctic: return .rain
        case .amber, .red: return .hex
        case .cyan, .magenta, .vapor: return .horizon
        }
    }

    /// Main neon color (rings, selection, text).
    var primary: RGB {
        switch self {
        case .green: return (0.22, 1.0, 0.08)
        case .matrix: return (0.0, 1.0, 0.25)
        case .cyan: return (0.0, 0.94, 1.0)
        case .magenta: return (1.0, 0.17, 0.84)
        case .vapor: return (1.0, 0.44, 0.81)
        case .amber: return (1.0, 0.69, 0.0)
        case .red: return (1.0, 0.13, 0.2)
        case .purple: return (0.69, 0.32, 1.0)
        case .arctic: return (0.88, 0.97, 1.0)
        }
    }

    /// Secondary accent (rotating arcs, laser, HUD labels).
    var secondary: RGB {
        switch self {
        case .green: return (0.0, 1.0, 0.78)
        case .matrix: return (0.0, 0.56, 0.07)
        case .cyan: return (1.0, 0.62, 0.0)
        case .magenta: return (0.0, 0.9, 1.0)
        case .vapor: return (0.0, 0.8, 1.0)
        case .amber: return (1.0, 0.3, 0.0)
        case .red: return (1.0, 0.85, 0.85)
        case .purple: return (1.0, 0.31, 0.85)
        case .arctic: return (0.5, 0.86, 1.0)
        }
    }

    /// Background gradient: center → edge.
    var background: (RGB, RGB) {
        switch self {
        case .green: return ((0.02, 0.08, 0.03), (0, 0, 0))
        case .matrix: return ((0.0, 0.05, 0.01), (0, 0, 0))
        case .cyan: return ((0.0, 0.06, 0.1), (0.0, 0.01, 0.03))
        case .magenta: return ((0.12, 0.02, 0.18), (0.02, 0.0, 0.06))
        case .vapor: return ((0.17, 0.03, 0.27), (0.04, 0.0, 0.1))
        case .amber: return ((0.1, 0.05, 0.0), (0.02, 0.01, 0.0))
        case .red: return ((0.12, 0.0, 0.02), (0.02, 0.0, 0.0))
        case .purple: return ((0.07, 0.02, 0.12), (0.01, 0.0, 0.03))
        case .arctic: return ((0.03, 0.07, 0.12), (0.0, 0.01, 0.03))
        }
    }

    var color: Color { Self.color(primary) }
    var accent: Color { Self.color(secondary) }
    var dimColor: Color { Color(red: primary.0 * 0.5, green: primary.1 * 0.5, blue: primary.2 * 0.5) }
    var backgroundInner: Color { Self.color(background.0) }
    var backgroundOuter: Color { Self.color(background.1) }
    var glitchColors: (Color, Color) { (Self.color(secondary), Color(red: 1, green: 0, blue: 0.6)) }
    var nsColor: NSColor { NSColor(red: primary.0, green: primary.1, blue: primary.2, alpha: 1) }
    var nsAccent: NSColor { NSColor(red: secondary.0, green: secondary.1, blue: secondary.2, alpha: 1) }

    private static func color(_ c: RGB) -> Color { Color(red: c.0, green: c.1, blue: c.2) }
}

enum SwitcherSize: String, CaseIterable {
    case small, medium, large

    var title: String { rawValue.capitalized }
    var scale: CGFloat {
        switch self {
        case .small: return 0.75
        case .medium: return 0.88
        case .large: return 1.0
        }
    }
}

enum ShowDelay: String, CaseIterable {
    case instant, fast, native

    var title: String {
        switch self {
        case .instant: return "Instant"
        case .fast: return "Fast (90 ms)"
        case .native: return "Native-like (200 ms)"
        }
    }
    var seconds: Double {
        switch self {
        case .instant: return 0
        case .fast: return 0.09
        case .native: return 0.2
        }
    }
}

/// User preferences, persisted in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var theme: NeonTheme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    @Published var size: SwitcherSize { didSet { defaults.set(size.rawValue, forKey: "size") } }
    @Published var delay: ShowDelay { didSet { defaults.set(delay.rawValue, forKey: "delay") } }
    @Published var animations: Bool { didSet { defaults.set(animations, forKey: "animations") } }
    @Published var glitch: Bool { didSet { defaults.set(glitch, forKey: "glitch") } }
    @Published var scanlines: Bool { didSet { defaults.set(scanlines, forKey: "scanlines") } }
    @Published var showHiddenApps: Bool { didSet { defaults.set(showHiddenApps, forKey: "showHiddenApps") } }
    @Published var mouseHover: Bool { didSet { defaults.set(mouseHover, forKey: "mouseHover") } }
    @Published var stickyMode: Bool { didSet { defaults.set(stickyMode, forKey: "stickyMode") } }

    private init() {
        defaults.register(defaults: [
            "enabled": true,
            "theme": NeonTheme.green.rawValue,
            "size": SwitcherSize.large.rawValue,
            "delay": ShowDelay.fast.rawValue,
            "animations": true,
            "glitch": true,
            "scanlines": true,
            "showHiddenApps": true,
            "mouseHover": true,
            "stickyMode": false,
        ])
        enabled = defaults.bool(forKey: "enabled")
        theme = NeonTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .green
        size = SwitcherSize(rawValue: defaults.string(forKey: "size") ?? "") ?? .large
        delay = ShowDelay(rawValue: defaults.string(forKey: "delay") ?? "") ?? .fast
        animations = defaults.bool(forKey: "animations")
        glitch = defaults.bool(forKey: "glitch")
        scanlines = defaults.bool(forKey: "scanlines")
        showHiddenApps = defaults.bool(forKey: "showHiddenApps")
        mouseHover = defaults.bool(forKey: "mouseHover")
        stickyMode = defaults.bool(forKey: "stickyMode")
    }

    func resetToDefaults() {
        theme = .green
        size = .large
        delay = .fast
        animations = true
        glitch = true
        scanlines = true
        showHiddenApps = true
        mouseHover = true
        stickyMode = false
    }
}
