import Foundation
import Supabase

private struct MutualRow: Decodable {
    let id: UUID
    let phoneHash: String

    enum CodingKeys: String, CodingKey {
        case id
        case phoneHash = "phone_hash"
    }
}

private struct BoardRow: Decodable {
    let userId: UUID
    let emoji: String
    let checkedInAt: Date?

    enum CodingKeys: String, CodingKey {
        case emoji
        case userId = "user_id"
        case checkedInAt = "checked_in_at"
    }
}

/// The widget's read of the board: the same two RPCs the app's board makes,
/// with names resolved from the map the app keeps in the App Group
/// container rather than from Contacts, which a widget cannot read.
///
/// The session comes from the keychain the app writes; the widget's
/// entitlement lists the app's keychain group first, so a token refresh
/// made here lands where the app looks too.
enum SkyRepository {
    static func load() async -> SkySnapshot {
        guard let session = try? await Supa.client.auth.session else { return .signedOut }
        let myId = session.user.id
        let day = LocalDay.string()
        do {
            let snapshot = try await withRetries { try await fetch(day: day, myId: myId) }
            SkySnapshotStore.save(snapshot)
            return snapshot
        } catch {
            // A widget refreshes when the system feels like it, which is
            // often when the phone is locked and the network is asleep. The
            // last good sky is still true — only older — and showing it
            // beats replacing a friend's mood with an error. Only today's,
            // though: yesterday's moods presented as today's would be a lie.
            if var cached = SkySnapshotStore.load(), cached.day == day, cached.state == .ready {
                cached.isStale = true
                return cached
            }
            return .failed
        }
    }

    /// One attempt at the board: two requests that don't depend on each
    /// other, so they overlap.
    private static func fetch(day: String, myId: UUID) async throws -> SkySnapshot {
        async let mutuals: [MutualRow] = Supa.client.rpc("my_mutuals").execute().value
        async let rows: [BoardRow] = Supa.client
            .rpc("board_today", params: ["for_day": day])
            .execute()
            .value
        let (links, board) = try await (mutuals, rows)
        let byUser = Dictionary(board.map { ($0.userId, $0) }, uniquingKeysWith: { first, _ in first })
        let friends = links.map { link in
            let row = byUser[link.id]
            return SkyFriend(
                id: link.id,
                name: NameMap.name(for: link.phoneHash) ?? "Friend",
                emoji: row?.emoji,
                checkedInAt: row?.checkedInAt
            )
        }
        return SkySnapshot(
            state: .ready, day: day, mine: byUser[myId]?.emoji, friends: SkySnapshot.sorted(friends),
            wildcard: MoodEmoji.wildcard(for: myId, day: day)
        )
    }

    /// The two failures a widget refresh actually hits. Clock skew is the
    /// one the app has always retried — PostgREST rejects a token whose
    /// `iat` is a second ahead of its clock, and a widget meets it more
    /// often than the app because it refreshes the token and calls in the
    /// same breath. A dropped connection gets one more try as well.
    private static func withRetries<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await withSkewRetry(operation)
        } catch where error.isTransientNetwork {
            try await Task.sleep(for: .seconds(1))
            return try await withSkewRetry(operation)
        }
    }
}
