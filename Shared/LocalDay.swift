import Foundation

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

extension Date {
    /// The timestamp `checkins.updated_at` is written with. `.iso8601` is a
    /// format style, so unlike `ISO8601DateFormatter()` it allocates
    /// nothing per save — and the app and the widget send the identical
    /// shape, which matters because either may write the same row.
    var storedTimestamp: String { formatted(.iso8601) }
}
