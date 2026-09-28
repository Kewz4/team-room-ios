import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b, a: Double
        if cleaned.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

/// Warm-neutral console palette with one muted pine accent (Team Room identity),
/// semantic working/idle/failure colors, and light/dark variants for every token.
enum Tokens {
    static let accent = Color(light: "2F6E57", dark: "5CB894")
    static let accentSoft = Color(light: "E4F0EA", dark: "1B342B")

    static let background = Color(light: "F7F6F3", dark: "121315")
    static let surface = Color(light: "FFFFFF", dark: "1C1D20")
    static let surfaceAlt = Color(light: "EDECE7", dark: "232529")
    static let hairline = Color(light: "E2E0D9", dark: "2F3136")

    static let textPrimary = Color(light: "1B1C1E", dark: "F1F1F2")
    static let textSecondary = Color(light: "6E6B63", dark: "9C9C9F")
    static let textTertiary = Color(light: "9C988E", dark: "6C6D71")

    static let working = Color(light: "B4560A", dark: "E8A24C")
    static let idle = Color(light: "3E8E6E", dark: "6FC49D")
    static let failure = Color(light: "B3382C", dark: "E06A5E")

    enum Space {
        static let hair: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 18
    }
}

enum TypeScale {
    static let screenTitle = Font.system(size: 28, weight: .semibold)
    static let title = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 16)
    static let subhead = Font.system(size: 15, weight: .medium)
    static let caption = Font.system(size: 12)
    static let captionMedium = Font.system(size: 12, weight: .medium)
    static let mono = Font.system(size: 12, design: .monospaced)
    static let monoSmall = Font.system(size: 11, design: .monospaced)
}
