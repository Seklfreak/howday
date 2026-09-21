import Foundation
import Testing
@testable import Howday

struct LocalDayTests {
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0, second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return Calendar.current.date(from: components)!
    }

    @Test func formatsTheLocalCalendarDate() {
        #expect(LocalDay.string(for: date(2026, 3, 7)) == "2026-03-07")
        #expect(LocalDay.string(for: date(2026, 12, 31)) == "2026-12-31")
    }

    @Test func midnightIsTheBoundary() {
        #expect(LocalDay.string(for: date(2026, 9, 19, hour: 23, minute: 59, second: 59)) == "2026-09-19")
        #expect(LocalDay.string(for: date(2026, 9, 20, hour: 0, minute: 0, second: 0)) == "2026-09-20")
    }

    /// The history sheet parses `checkins.day` back with this exact style.
    /// Written and read in two different files, so the pairing is worth
    /// holding down: a mismatch shows the raw "2026-09-20" to the user.
    @Test func theStoredDayParsesBackWithTheSheetsStyle() {
        let style = Date.ISO8601FormatStyle(dateSeparator: .dash, timeZone: .current).year().month().day()
        for day in [date(2026, 9, 20), date(2026, 1, 1), date(2026, 12, 31)] {
            let stored = LocalDay.string(for: day)
            let parsed = try? Date(stored, strategy: style)
            #expect(parsed != nil, "\(stored)")
            #expect(parsed.map { LocalDay.string(for: $0) } == stored, "\(stored)")
        }
    }

    /// What `checkins.updated_at` is written with by both the app and the
    /// widget — the server rejects anything it can't read as a timestamp.
    @Test func theStoredTimestampIsISO8601() {
        let moment = Date(timeIntervalSince1970: 1_790_000_000)
        let text = moment.storedTimestamp
        #expect(text.hasSuffix("Z"), "\(text)")
        let parsed = try? Date(text, strategy: .iso8601)
        #expect(parsed != nil, "\(text)")
        #expect(abs(parsed?.timeIntervalSince(moment) ?? .infinity) < 1)
    }

    /// The keys sort as dates, which the reminder planner and the queue's
    /// expiry both rely on.
    @Test func keysSortChronologically() {
        #expect(LocalDay.string(for: date(2026, 9, 9)) < LocalDay.string(for: date(2026, 9, 10)))
        #expect(LocalDay.string(for: date(2026, 12, 31)) < LocalDay.string(for: date(2027, 1, 1)))
    }
}
