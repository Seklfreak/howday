import Foundation
import Supabase

struct Checkin: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let userId: UUID
    let day: String
    var emoji: String
    /// When the check-in was made. Only `board_today` returns it; the plain
    /// select leaves it nil. The widget lays friends out along the day with
    /// it, so the app has to carry it into the snapshot it publishes rather
    /// than dropping it on the floor the way it used to.
    var checkedInAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, day, emoji
        case userId = "user_id"
        case checkedInAt = "checked_in_at"
    }
}

/// The upsert body for saveToday.
private struct CheckinPayload: Encodable {
    let userId: UUID
    let day: String
    let emoji: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case day, emoji
        case userId = "user_id"
        case updatedAt = "updated_at"
    }
}

struct CheckinRepository {
    static let columns = "id, user_id, day, emoji"

    func today() async throws -> Checkin? {
        let userId = try await Supa.client.auth.session.user.id
        let rows: [Checkin] = try await Supa.client
            .from("checkins")
            .select(Self.columns)
            .eq("user_id", value: userId)
            .eq("day", value: LocalDay.string())
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Insert or update today's check-in. Always targets the current local
    /// day, which is what enforces "editable until midnight": yesterday's row
    /// simply can't be addressed from the UI.
    func saveToday(emoji: String) async throws {
        try await withTrace("checkin.save") {
            let userId = try await Supa.client.auth.session.user.id
            let payload = CheckinPayload(
                userId: userId,
                day: LocalDay.string(),
                emoji: emoji,
                updatedAt: Date.now.storedTimestamp
            )
            try await Supa.client
                .from("checkins")
                .upsert(payload, onConflict: "user_id,day", returning: .minimal)
                .execute()
        }
    }

    /// The signed-in user's check-ins between two local days (inclusive),
    /// for the history calendar.
    func mine(from firstDay: String, to lastDay: String) async throws -> [Checkin] {
        let userId = try await Supa.client.auth.session.user.id
        return try await Supa.client
            .from("checkins")
            .select(Self.columns)
            .eq("user_id", value: userId)
            .gte("day", value: firstDay)
            .lte("day", value: lastDay)
            .order("day")
            .execute()
            .value
    }
}
