import AppKit
import SwiftUI

enum OrbitTheme {
    static var accent: Color {
        Color(hex: UserDefaults.standard.string(forKey: "orbit:accent") ?? "8B5CF6")
    }
    static let cobalt = Color(hex: "3D6DF2")
    static let emerald = Color(hex: "10B981")
    static let amber = Color(hex: "F59E0B")
    static let rose = Color(hex: "F43F5E")
    static let teal = Color(hex: "0EA5A8")
    static let sky = Color(hex: "0EA5E9")
    static let indigo = Color(hex: "6366F1")
    static let pink = Color(hex: "EC4899")
    static let orange = Color(hex: "F97316")
    static let lime = Color(hex: "84CC16")
    static let cyan = Color(hex: "06B6D4")

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "131211") : Color(hex: "F7F6F3")
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "1C1A18") : Color(hex: "FFFEFC")
    }

    static func sunken(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "262421") : Color(hex: "F2F0EC")
    }

    static func line(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "2C2A26") : Color(hex: "E9E7E1")
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "F1EFEB") : Color(hex: "1C1A17")
    }

    static func ink2(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "A19D94") : Color(hex: "6F6B63")
    }

    static func ink3(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "6D6961") : Color(hex: "A5A199")
    }

    static func accentSoft(_ scheme: ColorScheme) -> Color {
        accent.opacity(scheme == .dark ? 0.22 : 0.12)
    }

    static func habitColor(_ slug: String) -> Color {
        switch slug {
        case "cobalt": cobalt
        case "emerald": emerald
        case "violet": accent
        case "amber": amber
        case "rose": rose
        case "teal": teal
        case "sky": sky
        case "indigo": indigo
        case "pink": pink
        case "orange": orange
        case "lime": lime
        case "cyan": cyan
        default: accent
        }
    }
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    func orbitHex() -> String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
    }
}

struct OrbitCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(OrbitTheme.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(OrbitTheme.line(scheme), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.14 : 0.035), radius: 2, y: 1)
    }
}

extension View {
    func orbitCard() -> some View { modifier(OrbitCardModifier()) }
}
