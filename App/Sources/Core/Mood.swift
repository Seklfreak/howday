import Foundation

/// The five suggested check-in emoji, roughly rough → great. Any emoji is
/// allowed — these are just the quick picks shown in the check-in form.
enum MoodEmoji {
    static let suggestions = ["😢", "😕", "😐", "🙂", "😄"]
}

extension String {
    /// True when the string is exactly one emoji grapheme (skin tones, ZWJ
    /// sequences, and flags all count as one).
    var isSingleEmoji: Bool {
        guard count == 1, let character = first else { return false }
        let scalars = character.unicodeScalars
        // Plain digits, #, and * report isEmoji, so additionally require
        // emoji presentation or a multi-scalar sequence (variation selector,
        // ZWJ, skin tone, keycap).
        return scalars.contains { $0.properties.isEmojiPresentation }
            || (scalars.first?.properties.isEmoji == true && scalars.count > 1)
    }

    /// The first emoji grapheme in the string, if any.
    var firstEmoji: String? {
        first(where: { String($0).isSingleEmoji }).map(String.init)
    }
}
