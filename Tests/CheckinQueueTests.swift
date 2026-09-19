import Foundation
import Testing
@testable import Howday

/// Serialised: the queue is a process-wide single entry, and every test
/// swaps in its own defaults suite.
@Suite(.serialized)
struct CheckinQueueTests {
    private let today = "2026-09-19"
    private let yesterday = "2026-09-18"

    init() {
        CheckinQueue.defaults = UserDefaults(suiteName: "CheckinQueueTests-\(UUID().uuidString)")!
    }

    private struct ServerRejected: Error {}

    @Test func nothingParkedIsNothingToDo() async {
        var saves: [String] = []
        let outcome = await CheckinQueue.drain(today: today) { saves.append($0) }
        #expect(outcome == .nothing)
        #expect(saves.isEmpty)
    }

    @Test func parkedEntryIsSavedAndCleared() async {
        let entry = CheckinQueue.Pending(emoji: "🙂", day: today, isEdit: false)
        CheckinQueue.pending = entry
        var saves: [String] = []
        let outcome = await CheckinQueue.drain(today: today) { saves.append($0) }
        #expect(outcome == .saved(entry))
        #expect(saves == ["🙂"])
        #expect(CheckinQueue.pending == nil)
    }

    @Test func stillOfflineKeepsTheEntry() async {
        let entry = CheckinQueue.Pending(emoji: "🙂", day: today, isEdit: false)
        CheckinQueue.pending = entry
        let outcome = await CheckinQueue.drain(today: today) { _ in
            throw URLError(.notConnectedToInternet)
        }
        #expect(outcome == .stillPending(entry))
        #expect(CheckinQueue.pending == entry)
    }

    @Test func serverRejectionDropsTheEntry() async {
        let entry = CheckinQueue.Pending(emoji: "🙂", day: today, isEdit: true)
        CheckinQueue.pending = entry
        let outcome = await CheckinQueue.drain(today: today) { _ in throw ServerRejected() }
        guard case .rejected(let dropped, _) = outcome else {
            Issue.record("expected .rejected, got \(outcome)")
            return
        }
        #expect(dropped == entry)
        #expect(CheckinQueue.pending == nil)
    }

    /// saveToday cannot backdate, and the queue must not become the way
    /// around that: yesterday's entry is dropped without a save.
    @Test func anEarlierDayExpiresWithoutSaving() async {
        let entry = CheckinQueue.Pending(emoji: "😢", day: yesterday, isEdit: false)
        CheckinQueue.pending = entry
        var saves: [String] = []
        let outcome = await CheckinQueue.drain(today: today) { saves.append($0) }
        #expect(outcome == .expired(entry))
        #expect(saves.isEmpty)
        #expect(CheckinQueue.pending == nil)
    }

    @Test func pendingForTodayIgnoresOtherDays() {
        CheckinQueue.pending = CheckinQueue.Pending(emoji: "😢", day: yesterday, isEdit: false)
        #expect(CheckinQueue.pendingForToday(today) == nil)
        CheckinQueue.pending = CheckinQueue.Pending(emoji: "🙂", day: today, isEdit: false)
        #expect(CheckinQueue.pendingForToday(today)?.emoji == "🙂")
    }

    /// A tap that lands while the retry is in flight replaces the entry;
    /// the retry finishing must not clear the newer one.
    @Test func aNewerEntryDuringTheRetrySurvives() async {
        let older = CheckinQueue.Pending(emoji: "😐", day: today, isEdit: false)
        let newer = CheckinQueue.Pending(emoji: "😄", day: today, isEdit: true)
        CheckinQueue.pending = older
        let outcome = await CheckinQueue.drain(today: today) { _ in CheckinQueue.pending = newer }
        #expect(outcome == .saved(older))
        #expect(CheckinQueue.pending == newer)
    }

    @Test func roundTripsThroughDefaults() {
        let entry = CheckinQueue.Pending(emoji: "🚀", day: today, isEdit: true)
        CheckinQueue.pending = entry
        #expect(CheckinQueue.pending == entry)
        CheckinQueue.pending = nil
        #expect(CheckinQueue.pending == nil)
    }
}
