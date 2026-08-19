import Foundation
import Supabase

struct BoardEntry: Identifiable, Sendable {
    let profile: FriendProfile
    let checkin: Checkin?
    var id: UUID { profile.id }
}

struct BoardState: Sendable {
    var mine: Checkin?
    var entries: [BoardEntry] = []
}

struct BoardRepository {
    /// Everyone's check-ins for the viewer's local today: RLS makes the
    /// single day-filtered query return exactly the viewer's own row plus
    /// accepted friends' rows. "Today" is the viewer's local day — a friend
    /// a few timezones ahead may briefly show "not yet" around midnight.
    func load() async throws -> BoardState {
        let myId = try await Supa.client.auth.session.user.id
        let friends = try await FriendsRepository().state().friends.map(\.profile)
        let rows: [Checkin] = try await Supa.client
            .from("checkins")
            .select(CheckinRepository.columns)
            .eq("day", value: LocalDay.string())
            .execute()
            .value
        let byUser = Dictionary(rows.map { ($0.userId, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = friends
            .map { BoardEntry(profile: $0, checkin: byUser[$0.id]) }
            .sorted {
                // Checked-in friends first, then alphabetical.
                if ($0.checkin == nil) != ($1.checkin == nil) { return $0.checkin != nil }
                return $0.profile.displayName < $1.profile.displayName
            }
        return BoardState(mine: byUser[myId], entries: entries)
    }
}
