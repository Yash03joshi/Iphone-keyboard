import UIKit

/// Gboard-like colors, matching the Android keyboard. Each adapts to light/dark mode.
enum Palette {
    static let background = dynamic(light: 0xE8EAED, dark: 0x202124)
    static let key = dynamic(light: 0xFFFFFF, dark: 0x3C4043)
    static let functionKey = dynamic(light: 0xCDD1D6, dark: 0x2D2E31)
    static let keyShadow = dynamic(light: 0xB4B8BD, dark: 0x121212)
    static let text = dynamic(light: 0x1F1F1F, dark: 0xE8EAED)
    static let muted = dynamic(light: 0x80868B, dark: 0x9AA0A6)
    static let accent = dynamic(light: 0x0B57D0, dark: 0x8AB4F8)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x202124)
    static let canvas = dynamic(light: 0xF8F9FA, dark: 0x2A2B2E)
    static let ink = dynamic(light: 0x111111, dark: 0xF1F3F4)
    static let chosen = dynamic(light: 0xD3E3FD, dark: 0x394457)
    static let divider = dynamic(light: 0xC4C7CC, dark: 0x4A4D51)
    static let danger = dynamic(light: 0xB3261E, dark: 0xF2B8B5)

    private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) }
    }

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
