import Foundation
import Supabase

/// Formats the user's LOCAL calendar date as yyyy-MM-dd — the value stored in
/// checkins.day. All "today" logic in the app goes through this, which is
/// what makes one-check-in-per-day work across timezones.
enum LocalDay {
    /// Building a DateFormatter costs ~80µs, and the history grid formats one
    /// date per day cell every time its body runs — so the formatter is kept,
    /// and rebuilt only when the calendar or time zone actually changes
    /// (travel, a settings change). Deliberately still a DateFormatter rather
    /// than Calendar.dateComponents arithmetic: the two disagree on Hebrew
    /// leap months, which would move the stored `day` key under those users.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var formatter: DateFormatter?
        private var key: String?

        func string(for date: Date) -> String {
            let calendar = Calendar.current
            let timeZone = TimeZone.current
            let key = "\(calendar.identifier)|\(timeZone.identifier)"
            lock.lock()
            defer { lock.unlock() }
            let formatter: DateFormatter
            if let cached = self.formatter, self.key == key {
                formatter = cached
            } else {
                formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.timeZone = timeZone
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd"
                self.formatter = formatter
                self.key = key
            }
            return formatter.string(from: date)
        }
    }

    private static let cache = Cache()

    static func string(for date: Date = .now) -> String {
        cache.string(for: date)
    }
}

struct Checkin: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    let day: String
    var emoji: String

    enum CodingKeys: String, CodingKey {
        case id, day, emoji
        case userId = "user_id"
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
                updatedAt: ISO8601DateFormatter().string(from: .now)
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
