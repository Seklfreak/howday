import Foundation
import Supabase

/// Formats the user's LOCAL calendar date as yyyy-MM-dd — the value stored in
/// checkins.day. All "today" logic in the app goes through this, which is
/// what makes one-check-in-per-day work across timezones.
enum LocalDay {
    static func string(for date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct Checkin: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    let day: String
    var emoji: String
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id, day, emoji, note
        case userId = "user_id"
    }
}

struct CheckinRepository {
    static let columns = "id, user_id, day, emoji, note"

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
    func saveToday(emoji: String, note: String?) async throws {
        struct Payload: Encodable {
            let user_id: UUID
            let day: String
            let emoji: String
            let note: String?
            let updated_at: String
        }
        let userId = try await Supa.client.auth.session.user.id
        let payload = Payload(
            user_id: userId,
            day: LocalDay.string(),
            emoji: emoji,
            note: note?.isEmpty == false ? note : nil,
            updated_at: ISO8601DateFormatter().string(from: .now)
        )
        try await Supa.client
            .from("checkins")
            .upsert(payload, onConflict: "user_id,day", returning: .minimal)
            .execute()
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
