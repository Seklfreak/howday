import Foundation
import Testing
@testable import Howday

/// The push writes a friend's mood straight into the stored sky, so this is
/// the piece standing between a push and what a locked phone draws. Pure by
/// design — the store around it is one load and one save.
struct SkySnapshotPatchTests {
    private static let anna = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private static let ben = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!

    private func sky(
        day: String = LocalDay.string(),
        state: SkySnapshot.State = .ready,
        stale: Bool = false
    ) -> SkySnapshot {
        var snapshot = SkySnapshot(
            state: state, day: day, mine: "🙂",
            friends: [
                SkyFriend(id: Self.anna, name: "Anna", emoji: nil, checkedInAt: nil),
                SkyFriend(id: Self.ben, name: "Ben", emoji: "😐", checkedInAt: .now.addingTimeInterval(-3600)),
            ]
        )
        snapshot.isStale = stale
        snapshot.fetchedAt = .now.addingTimeInterval(-3600)
        return snapshot
    }

    private func written(_ patch: SkySnapshot.Patch) throws -> SkySnapshot {
        guard case .written(let snapshot) = patch else {
            Issue.record("expected a written sky, got \(patch)")
            throw PatchError.notWritten
        }
        return snapshot
    }

    private enum PatchError: Error { case notWritten }

    @Test func aFriendsMoodLandsAndSortsToTheFront() throws {
        let when = Date.now
        let patched = try written(sky().applying(emoji: "😄", from: Self.anna, at: when))
        #expect(patched.friends.first?.id == Self.anna)
        #expect(patched.friends.first?.emoji == "😄")
        #expect(patched.friends.first?.checkedInAt == when)
        // Everyone else is left exactly as they were.
        #expect(patched.friends.last?.emoji == "😐")
    }

    /// The whole point: the widget serves this instead of reading the board,
    /// and `isFresh` is the gate it checks.
    @Test func thePatchedSkyIsWhatAWidgetWillServe() throws {
        let patched = try written(sky(stale: true).applying(emoji: "😄", from: Self.anna))
        #expect(patched.isFresh)
    }

    @Test func aSenderWhoIsNotOnTheSkyCannotBeAnsweredFor() {
        #expect(sky().applying(emoji: "😄", from: UUID()) == .cannotAnswer)
    }

    @Test func yesterdaysSkyCannotBeAnsweredFor() {
        let yesterday = LocalDay.string(for: .now.addingTimeInterval(-86_400))
        #expect(sky(day: yesterday).applying(emoji: "😄", from: Self.anna) == .cannotAnswer)
    }

    @Test func askyThatNeverLoadedCannotBeAnsweredFor() {
        #expect(sky(state: .failed).applying(emoji: "😄", from: Self.anna) == .cannotAnswer)
        #expect(sky(state: .signedOut).applying(emoji: "😄", from: Self.anna) == .cannotAnswer)
    }

    /// The case that separates the three outcomes: a push for a mood the
    /// sky already shows must not be read as "fall back", or it would spend
    /// a fetch and a reload proving nothing changed.
    @Test func aMoodTheSkyAlreadyShowsIsNeitherWrittenNorAFallback() throws {
        let already = try written(sky().applying(emoji: "😄", from: Self.anna))
        #expect(already.applying(emoji: "😄", from: Self.anna) == .alreadyShown)
    }

    /// An edit — the other thing the trigger pushes for.
    @Test func aChangedMoodOverwritesTheOldOne() throws {
        let patched = try written(sky().applying(emoji: "🔥", from: Self.ben))
        #expect(patched.friends.first?.id == Self.ben)
        #expect(patched.friends.first?.emoji == "🔥")
    }
}
