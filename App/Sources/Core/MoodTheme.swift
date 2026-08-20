import CryptoKit
import SwiftUI

/// The mood-ring color language: every emoji resolves to three colors, mapped
/// from the real thermochromic ring chart for the five suggestions — on a real
/// ring violet is the *happiest* color and the rough end goes dark, not red,
/// with brightness and glow increasing toward the happy end. Any other emoji
/// (wildcards) gets a deterministic hue hashed from the emoji itself, so every
/// emoji keeps its color forever, on every device.
struct MoodTheme: Equatable {
    /// Rings, strokes, and the app tint.
    let accent: Color
    /// The background's base.
    let deep: Color
    /// The background's soft blooms.
    let glow: Color

    /// The unworn ring: pearl-neutral, shown before today's check-in.
    static let neutral = MoodTheme(0xA9A3B8, 0x1B1922, 0x4E4761)

    /// The app's resting accent (the scale's blissful violet) — the tint for
    /// sign-in and onboarding, before any mood exists to derive one from.
    /// HomeView overrides it with the current mood's accent.
    static let brand = MoodTheme(0xB08CFF, 0x221A33, 0x7A5CD6)

    private static let scale: [String: MoodTheme] = [
        "😢": MoodTheme(0x8B79A8, 0x241E30, 0x5A4A78), // plum-charcoal — the ring's "stressed" black
        "😕": MoodTheme(0xE3A554, 0x2A2118, 0x9C6A2E), // amber — unsettled
        "😐": MoodTheme(0x5FBF8F, 0x16261E, 0x2E7A55), // green — calm baseline
        "🙂": MoodTheme(0x56AECB, 0x14242B, 0x2E6F8C), // teal-blue — relaxed
        "😄": MoodTheme(0xB08CFF, 0x221A33, 0x7A5CD6), // violet — blissful, maximum glow
    ]

    static func forEmoji(_ emoji: String?) -> MoodTheme {
        guard let emoji else { return .neutral }
        return scale[emoji] ?? hashed(emoji)
    }

    /// Emoji outside the scale get a hue from SHA256 (not Hasher — Swift's
    /// Hasher is seeded per-process), styled to sit alongside the fixed scale.
    private static func hashed(_ emoji: String) -> MoodTheme {
        let digest = SHA256.hash(data: Data(emoji.utf8))
        let value = digest.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let hue = Double(value % 360) / 360
        return MoodTheme(
            accent: Color(hue: hue, saturation: 0.45, brightness: 0.88),
            deep: Color(hue: hue, saturation: 0.38, brightness: 0.15),
            glow: Color(hue: hue, saturation: 0.55, brightness: 0.42)
        )
    }

    init(accent: Color, deep: Color, glow: Color) {
        self.accent = accent
        self.deep = deep
        self.glow = glow
    }

    private init(_ accent: UInt32, _ deep: UInt32, _ glow: UInt32) {
        self.init(accent: Color(hex: accent), deep: Color(hex: deep), glow: Color(hex: glow))
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
