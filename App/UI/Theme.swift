import SwiftUI

enum Space {
    static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
}

enum Radius {
    static let sm: CGFloat = 6, md: CGFloat = 10, lg: CGFloat = 14
}

enum TypeStyle {
    static let title = Font.title.weight(.bold)
    static let headline = Font.title3.weight(.semibold)
    static let heading = Font.footnote.weight(.semibold)
    static let body = Font.body
    static let label = Font.body.weight(.medium)
    static let caption = Font.footnote
    static let mono = Font.system(.footnote, design: .monospaced)
    static let headingTracking: CGFloat = 0.6
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

struct Palette: Sendable {
    let bg, card, text, dim, faint, hairline, accent, accentSoft, onAccent, late, lateSoft, warn, done, past, backdrop: Color

    static let light = Palette(
        bg: Color(hex: 0xF2F2F7), card: Color(hex: 0xFFFFFF), text: Color(hex: 0x101014), dim: Color(hex: 0x6B6B76),
        faint: Color(hex: 0xAEAEB6), hairline: Color(hex: 0xE2E2E8), accent: Color(hex: 0x2F6FEB),
        accentSoft: Color(hex: 0xE6EEFD), onAccent: Color(hex: 0xFFFFFF), late: Color(hex: 0xC7371F),
        lateSoft: Color(hex: 0xFBE9E6), warn: Color(hex: 0xB26A00), done: Color(hex: 0x1F7A46),
        past: Color(hex: 0x9A9AA5), backdrop: Color(hex: 0x000000, alpha: 0.33))

    static let dark = Palette(
        bg: Color(hex: 0x000000), card: Color(hex: 0x1C1C1F), text: Color(hex: 0xF2F2F5), dim: Color(hex: 0x9A9AA5),
        faint: Color(hex: 0x5A5A64), hairline: Color(hex: 0x2C2C33), accent: Color(hex: 0x5C8DF6),
        accentSoft: Color(hex: 0x1B2A4A), onAccent: Color(hex: 0xFFFFFF), late: Color(hex: 0xF0705A),
        lateSoft: Color(hex: 0x3A1C17), warn: Color(hex: 0xE0A04A), done: Color(hex: 0x4FB37A),
        past: Color(hex: 0x6B6B76), backdrop: Color(hex: 0x000000, alpha: 0.53))

    static func `for`(_ scheme: ColorScheme) -> Palette { scheme == .dark ? dark : light }
}

extension EnvironmentValues {
    /// Follows the current color scheme; use `@Environment(\.palette) private var p`.
    var palette: Palette { Palette.for(colorScheme) }
}

/// Text as VoiceOver should say it, without the decorative glyphs.
func spoken(_ text: String) -> String {
    var s = text.replacingOccurrences(of: "(\\d)\\+", with: "$1 and over", options: .regularExpression)
    s = s.replacingOccurrences(of: "(^|\\s)[+!](?=\\s|$)", with: " ", options: .regularExpression)
    s = s.replacingOccurrences(of: "[⚠›‹⌄▾▴✎○●＋✓✕]", with: " ", options: .regularExpression)
    s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    s = s.replacingOccurrences(of: "\\s+,", with: ",", options: .regularExpression)
    return s.trimmingCharacters(in: .whitespaces)
}
