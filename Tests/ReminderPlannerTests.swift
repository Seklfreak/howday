import Foundation
import Testing
@testable import Howday

/// `ReminderScheduler.plan` is the booking logic minus the random draw and
/// the notification center. Times are built in the current calendar, which
/// is what the scheduler itself uses.
struct ReminderPlannerTests {
    private let windowStart = 8 * 60
    private let windowEnd = 22 * 60

    private func now(hour: Int, minute: Int = 0) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    private func day(offset: Int, from date: Date) -> String {
        LocalDay.string(for: Calendar.current.date(byAdding: .day, value: offset, to: date)!)
    }

    @Test func booksTheWholeHorizonFromToday() {
        let at = now(hour: 10)
        let planned = ReminderScheduler.plan(
            after: "", windowStart: windowStart, windowEnd: windowEnd, checkedInDay: nil, now: at
        )
        #expect(planned.slots.count == ReminderScheduler.horizonDays)
        #expect(planned.slots.first?.day == day(offset: 0, from: at))
        #expect(planned.lastDay == day(offset: ReminderScheduler.horizonDays - 1, from: at))
        // Every later day gets the full window.
        for slot in planned.slots.dropFirst() {
            #expect(slot.window == windowStart...windowEnd, "\(slot.day)")
        }
    }

    @Test func todayGetsWhatIsLeftOfTheWindow() {
        let at = now(hour: 10, minute: 30)
        let planned = ReminderScheduler.plan(
            after: "", windowStart: windowStart, windowEnd: windowEnd, checkedInDay: nil, now: at
        )
        // 10:30 plus the one-minute guard against a trigger in the past.
        #expect(planned.slots.first?.window == (10 * 60 + 31)...windowEnd)
    }

    @Test func todayIsSkippedOnceTheWindowHasClosed() {
        let at = now(hour: 23)
        let planned = ReminderScheduler.plan(
            after: "", windowStart: windowStart, windowEnd: windowEnd, checkedInDay: nil, now: at
        )
        #expect(planned.slots.count == ReminderScheduler.horizonDays - 1)
        #expect(planned.slots.first?.day == day(offset: 1, from: at))
        // Still recorded as planned, or the next foreground would try again.
        #expect(planned.lastDay == day(offset: ReminderScheduler.horizonDays - 1, from: at))
    }

    @Test func daysAlreadyPlannedAreNotBookedTwice() {
        let at = now(hour: 10)
        let alreadyPlanned = day(offset: 5, from: at)
        let planned = ReminderScheduler.plan(
            after: alreadyPlanned, windowStart: windowStart, windowEnd: windowEnd, checkedInDay: nil, now: at
        )
        #expect(planned.slots.first?.day == day(offset: 6, from: at))
        #expect(planned.slots.count == ReminderScheduler.horizonDays - 6)
    }

    @Test func nothingToBookPastTheHorizon() {
        let at = now(hour: 10)
        let farAhead = day(offset: 30, from: at)
        let planned = ReminderScheduler.plan(
            after: farAhead, windowStart: windowStart, windowEnd: windowEnd, checkedInDay: nil, now: at
        )
        #expect(planned.slots.isEmpty)
        #expect(planned.lastDay == farAhead)
    }

    @Test func aCheckedInDayIsSkippedButStillCounted() {
        let at = now(hour: 10)
        let today = day(offset: 0, from: at)
        let planned = ReminderScheduler.plan(
            after: "", windowStart: windowStart, windowEnd: windowEnd, checkedInDay: today, now: at
        )
        #expect(planned.slots.first?.day == day(offset: 1, from: at))
        #expect(planned.slots.count == ReminderScheduler.horizonDays - 1)
        #expect(planned.lastDay == day(offset: ReminderScheduler.horizonDays - 1, from: at))
    }

    @Test func slotsNeverStartBeforeTheWindow() {
        let at = now(hour: 6)
        let planned = ReminderScheduler.plan(
            after: "", windowStart: windowStart, windowEnd: windowEnd, checkedInDay: nil, now: at
        )
        #expect(planned.slots.first?.window == windowStart...windowEnd)
    }
}
