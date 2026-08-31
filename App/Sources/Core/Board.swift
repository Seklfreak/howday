import Foundation
import Supabase
import UIKit

/// A contact thumbnail, decoded once off the main actor. UIImage isn't
/// Sendable, but one that is decoded and then never mutated is safe to hand
/// across actors — which is the whole point of decoding it here rather than
/// in the card's body.
struct Avatar: @unchecked Sendable {
    let image: UIImage
}

struct BoardEntry: Identifiable, Sendable {
    let id: UUID
    let identity: ContactDirectory.Identity
    let checkin: Checkin?
    let avatar: Avatar?
}

struct BoardState: Sendable {
    var mine: Checkin?
    var entries: [BoardEntry] = []
}

struct BoardRepository {
    /// Build the board from mutual contacts: RLS makes the single
    /// day-filtered checkins query return exactly the viewer's own row plus
    /// mutual contacts' rows. "Today" is the viewer's local day — a friend a
    /// few timezones ahead may briefly show "not yet" around midnight.
    /// Contact syncing is NOT done here (see ContactDirectory.syncIfNeeded);
    /// this stays cheap enough to run on every realtime event.
    func load() async throws -> BoardState {
        let myId = try await Supa.client.auth.session.user.id
        // Nothing links these two requests, and run back to back they were
        // most of the load: 131ms for the RPC then 123ms for the select, at
        // p50. Overlapping them costs the slower of the two instead.
        async let mutuals = ContactDirectory.fetchMutuals()
        async let today: [Checkin] = Supa.client
            .from("checkins")
            .select(CheckinRepository.columns)
            .eq("day", value: LocalDay.string())
            .execute()
            .value
        let (friends, rows) = try await (mutuals, today)
        let byUser = Dictionary(rows.map { ($0.userId, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = friends
            .map {
                BoardEntry(
                    id: $0.id,
                    identity: $0.identity,
                    checkin: byUser[$0.id],
                    avatar: avatar(from: $0.identity.photo)
                )
            }
            .sorted {
                // Checked-in friends first, then alphabetical.
                if ($0.checkin == nil) != ($1.checkin == nil) { return $0.checkin != nil }
                return $0.identity.name < $1.identity.name
            }
        return BoardState(mine: byUser[myId], entries: entries)
    }

    /// UIImage(data:) decodes lazily, so leaving this to the card's body put
    /// a decode of every thumbnail on the main thread — again on each scroll
    /// pass and each reload. `load()` is nonisolated, so this runs off it.
    private func avatar(from data: Data?) -> Avatar? {
        guard let data, let image = UIImage(data: data) else { return nil }
        return Avatar(image: image.preparingForDisplay() ?? image)
    }
}
