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

    /// The keys sort as dates, which the reminder planner and the queue's
    /// expiry both rely on.
    @Test func keysSortChronologically() {
        #expect(LocalDay.string(for: date(2026, 9, 9)) < LocalDay.string(for: date(2026, 9, 10)))
        #expect(LocalDay.string(for: date(2026, 12, 31)) < LocalDay.string(for: date(2027, 1, 1)))
    }
}
