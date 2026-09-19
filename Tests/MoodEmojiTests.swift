import Foundation
import Testing
@testable import Howday

struct MoodEmojiTests {
    @Test func wildcardPoolExcludesTheSuggestions() {
        for suggestion in MoodEmoji.suggestions {
            #expect(!MoodEmoji.all.contains(suggestion))
        }
        #expect(MoodEmoji.all.count > 500)
    }

    @Test func wildcardPoolIsSingleScalarEmojiPresentation() {
        for emoji in MoodEmoji.all {
            #expect(emoji.unicodeScalars.count == 1, "\(emoji)")
            #expect(emoji.unicodeScalars.first?.properties.isEmojiPresentation == true, "\(emoji)")
        }
    }

    /// Skin tones and the hair swatches have emoji presentation but only
    /// mean anything inside a ZWJ sequence; alone they render as a colour
    /// chip or a cropped scalp.
    @Test func wildcardPoolExcludesEmojiComponents() {
        let components: [ClosedRange<UInt32>] = [0x1F3FB...0x1F3FF, 0x1F9B0...0x1F9B3]
        for emoji in MoodEmoji.all {
            let value = emoji.unicodeScalars.first!.value
            #expect(!components.contains { $0.contains(value) }, "\(emoji)")
        }
    }

    @Test func wildcardIsStableForAUserAndDay() {
        let user = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        let first = MoodEmoji.wildcard(for: user, day: "2026-09-19")
        #expect(first == MoodEmoji.wildcard(for: user, day: "2026-09-19"))
        #expect(MoodEmoji.all.contains(first))
    }

    @Test func wildcardVariesAcrossDaysAndUsers() {
        let user = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        let other = UUID(uuidString: "6BA7B811-9DAD-11D1-80B4-00C04FD430C8")!
        let days = (1...30).map { String(format: "2026-09-%02d", $0) }
        let mine = Set(days.map { MoodEmoji.wildcard(for: user, day: $0) })
        let theirs = Set(days.map { MoodEmoji.wildcard(for: other, day: $0) })
        // 30 draws from a pool of hundreds: the same every day would be a
        // seeded-per-process hasher, which is the bug this guards against.
        #expect(mine.count > 10)
        #expect(mine != theirs)
    }
}
