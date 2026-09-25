import CryptoKit
import Foundation

/// The suggested check-in emoji — the first five roughly rough → great,
/// then three that sit off that scale — plus a daily wildcard. The data
/// model accepts any emoji — the form just offers these.
enum MoodEmoji {
    static let suggestions = ["😢", "😕", "😐", "🙂", "😄", "🫠", "🥱", "😷"]

    /// Every standalone emoji the wildcard can draw from: single scalars with
    /// default emoji presentation (so they render as emoji without a variation
    /// selector), minus the fixed suggestions. Built from the Unicode emoji
    /// blocks so new OS versions pick up new emoji automatically.
    static let all: [String] = {
        let blocks: [ClosedRange<UInt32>] = [
            0x1F300...0x1F5FF, // symbols & pictographs
            0x1F600...0x1F64F, // emoticons
            0x1F680...0x1F6FF, // transport & map
            0x1F900...0x1F9FF, // supplemental symbols
            0x1FA70...0x1FAFF, // symbols extended-A
            0x2600...0x27BF,   // misc symbols & dingbats
        ]
        return blocks.flatMap { block in
            block.compactMap { value -> String? in
                // Emoji *components* — the skin tones and the four hair
                // swatches — also have emoji presentation, but only mean
                // anything inside a ZWJ sequence. Alone, Apple draws them as
                // what they are: a colour chip, or the cropped corner of a
                // scalp, which in a mood badge reads as a clipped glyph.
                // Swift exposes no `isEmojiComponent`, so the hair four are
                // named by range.
                let hairComponents: ClosedRange<UInt32> = 0x1F9B0...0x1F9B3
                guard let scalar = Unicode.Scalar(value),
                      scalar.properties.isEmojiPresentation,
                      !scalar.properties.isEmojiModifier,
                      !hairComponents.contains(value) else { return nil }
                let emoji = String(scalar)
                return suggestions.contains(emoji) ? nil : emoji
            }
        }
    }()

    /// `count` of `choices` in a shuffled order, the same ones in the same
    /// order for the same seed. SHA256, not Hasher, for the same reason as
    /// the wildcard.
    static func pick(_ count: Int, from choices: [String], seed: String) -> [String] {
        let ranked = choices.indices.sorted { a, b in
            rank(a, seed) < rank(b, seed)
        }
        return ranked.prefix(count).map { choices[$0] }
    }

    private static func rank(_ index: Int, _ seed: String) -> UInt64 {
        let digest = SHA256.hash(data: Data("\(seed)|\(index)".utf8))
        return digest.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }

    /// The day's extra offer: deterministic for (user, local day), so it
    /// survives app restarts but differs between users and changes each day.
    /// SHA256, not Hasher — Swift's Hasher is seeded per-process.
    static func wildcard(for userId: UUID, day: String) -> String {
        let digest = SHA256.hash(data: Data("\(userId.uuidString)|\(day)".utf8))
        let value = digest.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return all[Int(value % UInt64(all.count))]
    }
}
