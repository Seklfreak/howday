import CryptoKit
import SwiftUI

/// The mood-ring color language: every emoji resolves to three colors. The
/// five suggestions run cold → warm — a cold blue for sad, the sun for joyful,
/// an even teal at the midpoint — because that is the ring people *read*: the
/// real thermochromic chart (black → amber → green → blue → violet) put both
/// ends on purples and green on "meh", and nobody saw a mood in it. Accents sit
/// at full brightness and the deeps are tinted rather than near-black, so the
/// whole screen reads as a color. Any other emoji (wildcards) gets a
/// deterministic hue hashed from the emoji itself, so every emoji keeps its
/// color forever, on every device.
struct MoodTheme: Equatable {
    /// Rings, strokes, and the app tint.
    let accent: Color
    /// The background's base.
    let deep: Color
    /// The background's soft blooms.
    let glow: Color

    /// The unworn ring: pearl-neutral, shown before today's check-in.
    static let neutral = MoodTheme(0xA9A3B8, 0x1B1922, 0x4E4761)

    /// The app's resting accent (the scale's sunlight gold) — the tint for
    /// sign-in and onboarding, before any mood exists to derive one from.
    /// HomeView overrides it with the current mood's accent.
    static let brand = MoodTheme(0xFFC94A, 0x2F2208, 0xD8911A)

    private static let scale: [String: MoodTheme] = [
        "😢": MoodTheme(0x5B9BFF, 0x101E3C, 0x2C5BC9), // cold blue — feeling blue
        "😕": MoodTheme(0xA98BFF, 0x201740, 0x5F44CC), // brooding violet — twilight, unsettled
        "😐": MoodTheme(0x3FD3C2, 0x0B2826, 0x1A8A7E), // even teal — neither warm nor cold
        "🙂": MoodTheme(0x6CE08A, 0x0F2A18, 0x2E9B52), // fresh green — a good day
        "😄": MoodTheme(0xFFC94A, 0x2F2208, 0xD8911A), // sunlight gold — the emoji's own color
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
            accent: Color(hue: hue, saturation: 0.62, brightness: 1.0),
            deep: Color(hue: hue, saturation: 0.60, brightness: 0.22),
            glow: Color(hue: hue, saturation: 0.80, brightness: 0.62)
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

// MARK: - Carrying the mood further than a tint can

private struct MoodThemeKey: EnvironmentKey {
    static let defaultValue = MoodTheme.brand
}

extension EnvironmentValues {
    /// The mood the screen is dressed in. A `.tint` carries the accent and
    /// nothing else, and the accent alone is not enough to write on.
    var moodTheme: MoodTheme {
        get { self[MoodThemeKey.self] }
        set { self[MoodThemeKey.self] = newValue }
    }
}

extension View {
    /// Dresses a screen in a mood: the tint every control reads, and the
    /// theme behind it for the things a tint cannot say.
    func moodTheme(_ theme: MoodTheme) -> some View {
        environment(\.moodTheme, theme).tint(theme.accent)
    }

    /// For a label drawn on top of the accent — a filled button, chiefly.
    ///
    /// `.borderedProminent` writes white on the tint, and every accent in
    /// the scale is a bright colour: white on the gold is **1.53:1**, and
    /// never better than 2.8:1 on any of the others, against the 4.5:1 that
    /// body-sized text needs. The mood's own `deep` is between 6:1 and 10:1
    /// on the same fills. It has to sit inside the button's label, where it
    /// beats the style's own choice.
    func onAccent() -> some View {
        modifier(OnAccentLabel())
    }
}

private struct OnAccentLabel: ViewModifier {
    @Environment(\.moodTheme) private var theme

    func body(content: Content) -> some View {
        content.foregroundStyle(theme.deep)
    }
}
