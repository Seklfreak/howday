import Foundation

/// The one check-in the server has not acknowledged yet. The tap is the
/// whole product, and a tunnel used to eat it: the save failed, the picker
/// rolled back, and the day was lost unless the user remembered to try
/// again. A save that fails for want of a network is parked here instead
/// and retried on the next foreground, the next reachable network, and the
/// next launch.
///
/// Only ever one entry: a later tap for the same day supersedes it, and a
/// successful save clears it, so the last tap is still the one that sticks.
/// An entry for an earlier day is expired rather than saved — `saveToday`
/// deliberately cannot backdate, and this must not become the way around
/// that.
enum CheckinQueue {
    struct Pending: Codable, Equatable, Sendable {
        let emoji: String
        /// The local day the tap was made on, in `LocalDay` form.
        let day: String
        /// Whether the tap replaced a mood already saved that day — only the
        /// analytics event cares, so the funnel still counts it as an edit.
        let isEdit: Bool
    }

    enum Outcome: Equatable {
        /// Nothing was parked.
        case nothing
        /// The parked save went through.
        case saved(Pending)
        /// Still no network; the entry stays parked.
        case stillPending(Pending)
        /// The parked day has passed. Dropped, never saved.
        case expired(Pending)
        /// The server rejected it (auth, RLS, a 4xx): retrying would never
        /// help, so the entry is dropped and the caller shows the error.
        case rejected(Pending, String)
    }

    private static let key = "pendingCheckin"

    static var pending: Pending? {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(Pending.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                UserDefaults.standard.removeObject(forKey: key)
                return
            }
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Whether the parked entry, if any, is still for today — the only case
    /// in which its emoji is what the user should see selected.
    static func pendingForToday(_ today: String = LocalDay.string()) -> Pending? {
        guard let pending, pending.day == today else { return nil }
        return pending
    }

    /// Tries the parked save once. Callers serialise this with their own
    /// saves (HomeView chains it onto the save task) so a retry never races
    /// a fresh tap; the queue itself only guards against clearing an entry
    /// that a tap replaced while the retry was in flight.
    static func drain(
        today: String = LocalDay.string(),
        save: (String) async throws -> Void = { try await CheckinRepository().saveToday(emoji: $0) }
    ) async -> Outcome {
        guard let entry = pending else { return .nothing }
        guard entry.day == today else {
            pending = nil
            return .expired(entry)
        }
        do {
            try await withSkewRetry { try await save(entry.emoji) }
            if pending == entry { pending = nil }
            return .saved(entry)
        } catch where error.isTransientNetwork {
            return .stillPending(entry)
        } catch {
            if pending == entry { pending = nil }
            return .rejected(entry, error.report("checkin.drain"))
        }
    }
}
