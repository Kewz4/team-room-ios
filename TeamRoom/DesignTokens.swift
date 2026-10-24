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

    static let background = Color(light: "F7F6F3", dark: "111214")
    static let surface = Color(light: "FFFFFF", dark: "1B1C1F")
    static let surfaceAlt = Color(light: "EFEEE9", dark: "24262A")
    static let hairline = Color(light: "E2E0D9", dark: "2F3136")
    static let userBubble = Color(light: "E7F1EC", dark: "1F3A30")

    static let textPrimary = Color(light: "1B1C1E", dark: "F1F1F2")
    static let textSecondary = Color(light: "6E6B63", dark: "A3A3A7")
    static let textTertiary = Color(light: "9C988E", dark: "6F7075")

    static let working = Color(light: "B4560A", dark: "E8A24C")
    static let idle = Color(light: "3E8E6E", dark: "6FC49D")
    static let failure = Color(light: "B3382C", dark: "E06A5E")
    static let info = Color(light: "2F64B4", dark: "7DA8F0")

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
        static let xl: CGFloat = 24
    }
}

/// Dynamic Type text styles, so the whole app follows the iPhone's text size setting.
enum TypeScale {
    static let screenTitle = Font.largeTitle.weight(.semibold)
    static let title = Font.headline
    static let body = Font.body
    static let subhead = Font.subheadline.weight(.medium)
    static let caption = Font.caption
    static let captionMedium = Font.caption.weight(.medium)
    static let footnote = Font.footnote
    static let mono = Font.system(.footnote, design: .monospaced)
    static let monoSmall = Font.system(.caption2, design: .monospaced)
    static let number = Font.system(.title2, design: .rounded).weight(.semibold)
}

/// Each teammate keeps one colour everywhere: avatars, charts, board lanes and notifications.
enum AgentStyle {
    static func worker(for agent: Agent) -> String {
        if let worker = agent.worker, !worker.isEmpty { return worker }
        return worker(forId: agent.id)
    }

    static func worker(forId id: String) -> String {
        switch id {
        case "claude-assets": return "nova"
        case "gpt-world": return "atlas"
        case "gpt-assets": return "scout"
        case "opencode-world": return "flint"
        case "claude-adventure": return "sage"
        case "claude-polaris": return "polaris"
        case "claude-vega": return "vega"
        case "claude-orion": return "orion"
        case "claude-rigel": return "rigel"
        case "claude-lyra": return "lyra"
        default: return id
        }
    }

    static func color(_ worker: String?) -> Color {
        switch (worker ?? "").lowercased() {
        case "polaris": return Color(light: "B8860B", dark: "F2C14E")
        case "nova": return Color(light: "6E4CF5", dark: "9C85FF")
        case "atlas": return Color(light: "2563D9", dark: "6EA2FF")
        case "scout": return Color(light: "0F8F78", dark: "45C9AA")
        case "flint": return Color(light: "D9621A", dark: "FF9A52")
        case "sage": return Color(light: "3F8A3B", dark: "7FC874")
        // 1.2 (2026-10-04): Vega and Orion match their avatars in the web Team Room and the Bark notices. Nimbus
        // retired the same day; his colour stays for his history.
        case "vega": return Color(light: "B5235A", dark: "F0679E")
        case "orion": return Color(light: "B8312F", dark: "F06C5B")
        case "nimbus": return Color(light: "C93C6E", dark: "FF84AE")
        // 1.3 (2026-10-23): the API-credit workers get colours nobody else uses.
        case "rigel": return Color(light: "0C8FB8", dark: "56CCF2")
        case "lyra": return Color(light: "6F8A0C", dark: "B7D440")
        case "kewz", "you": return Tokens.accent
        case "coordinator": return Color(light: "5B6472", dark: "A8B0BC")
        default: return Tokens.textSecondary
        }
    }

    static func displayName(_ worker: String?) -> String {
        guard let worker, !worker.isEmpty else { return "Teammate" }
        if worker == "kewz" { return "You" }
        return worker.prefix(1).uppercased() + worker.dropFirst()
    }

    static func stateColor(_ state: String?) -> Color {
        switch state {
        case "working": return Tokens.working
        case "idle": return Tokens.idle
        default: return Tokens.textTertiary
        }
    }
}
