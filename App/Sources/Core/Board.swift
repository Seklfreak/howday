import Foundation
import Supabase

struct BoardEntry: Identifiable, Sendable {
    let id: UUID
    let identity: ContactDirectory.Identity
    let checkin: Checkin?
}

struct BoardState: Sendable {
    var mine: Checkin?
    var entries: [BoardEntry] = []
}

struct BoardRepository {
    /// Sync the address book, then build the board from mutual contacts:
    /// RLS makes the single day-filtered checkins query return exactly the
    /// viewer's own row plus mutual contacts' rows. "Today" is the viewer's
    /// local day — a friend a few timezones ahead may briefly show "not yet"
    /// around midnight.
    func load() async throws -> BoardState {
        let myId = try await Supa.client.auth.session.user.id
        let friends = try await ContactDirectory.syncAndFetchMutuals()
        let rows: [Checkin] = try await Supa.client
            .from("checkins")
            .select(CheckinRepository.columns)
            .eq("day", value: LocalDay.string())
            .execute()
            .value
        let byUser = Dictionary(rows.map { ($0.userId, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = friends
            .map { BoardEntry(id: $0.id, identity: $0.identity, checkin: byUser[$0.id]) }
            .sorted {
                // Checked-in friends first, then alphabetical.
                if ($0.checkin == nil) != ($1.checkin == nil) { return $0.checkin != nil }
                return $0.identity.name < $1.identity.name
            }
        return BoardState(mine: byUser[myId], entries: entries)
    }
}
