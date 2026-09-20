import Foundation
import Supabase

/// What a widget timeline entry carries. Friends are sorted the way the
/// layout wants them: checked in first, most recent first, then the rest
/// by name.
struct SkySnapshot: Hashable, Sendable {
    enum State: Hashable, Sendable {
        case signedOut
        case failed
        case ready
    }

    let state: State
    /// The local day the snapshot describes, `LocalDay` form.
    let day: String
    /// Your own emoji today — nil is the gate: friends' moods stay hidden.
    let mine: String?
    let friends: [SkyFriend]

    var friendsIn: Int { friends.filter(\.isIn).count }

    static let signedOut = SkySnapshot(state: .signedOut, day: LocalDay.string(), mine: nil, friends: [])
    static let failed = SkySnapshot(state: .failed, day: LocalDay.string(), mine: nil, friends: [])

    /// What the gallery and a redacted widget show: a full sky.
    static var placeholder: SkySnapshot {
        // Clock times rather than "minutes ago": the large widget lays the
        // day out left to right, and a sample that all happened just now
        // would stack in the evening column.
        let calendar = Calendar.current
        func sample(_ index: Int, _ name: String, _ emoji: String?, at hour: Int, _ minute: Int) -> SkyFriend {
            SkyFriend(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)") ?? UUID(),
                name: name, emoji: emoji,
                checkedInAt: emoji == nil ? nil : calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now)
            )
        }
        let friends = [
            sample(1, "Anna", "😄", at: 9, 12), sample(2, "Sam", "🙂", at: 10, 5),
            sample(3, "Ben", "😐", at: 11, 40), sample(4, "Jonas", "😕", at: 14, 20),
            sample(5, "Chloé", "😢", at: 17, 48), sample(6, "Dev", nil, at: 0, 0),
            sample(7, "Mira", nil, at: 0, 0),
        ]
        return SkySnapshot(state: .ready, day: LocalDay.string(), mine: "🙂", friends: SkySnapshot.sorted(friends))
    }

    static func sorted(_ friends: [SkyFriend]) -> [SkyFriend] {
        friends.sorted { lhs, rhs in
            switch (lhs.checkedInAt, rhs.checkedInAt) {
            case let (left?, right?): return left > right
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.name < rhs.name
            }
        }
    }
}

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
            return SkySnapshot(state: .ready, day: day, mine: byUser[myId]?.emoji, friends: SkySnapshot.sorted(friends))
        } catch {
            return .failed
        }
    }
}
