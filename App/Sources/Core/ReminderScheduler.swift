import Foundation
import UserNotifications

/// The daily "how are you?" local notification. Fires at a different random
/// minute each day, inside a window the user picks. Everything is on-device —
/// no APNs, no server involvement.
///
/// A repeating calendar trigger can't vary its time, so one non-repeating
/// request is booked per day for the next `horizonDays` days, and the plan is
/// topped up every time the app comes to the foreground. The last day booked
/// is remembered under `lastPlannedDay`, so a day whose request has already
/// fired (and is therefore no longer pending) is never booked a second time.
enum ReminderScheduler {
    /// Minutes since midnight. The defaults are 8:00 and 22:00.
    static let defaultWindowStart = 8 * 60
    static let defaultWindowEnd = 22 * 60

    static let enabledKey = "reminderEnabled"
    static let configuredKey = "reminderConfigured"
    static let windowStartKey = "reminderWindowStart"
    static let windowEndKey = "reminderWindowEnd"

    /// Days booked ahead. Well under the 64 pending local notifications iOS
    /// allows, and long enough that a fortnight without opening the app
    /// still gets a nudge every day.
    static let horizonDays = 14

    private static let requestPrefix = "daily-checkin-"
    /// The single repeating request older builds scheduled.
    private static let legacyRequestId = "daily-checkin"
    private static let lastPlannedDayKey = "reminderLastPlannedDay"
    /// The day whose reminder was cancelled because the user already checked
    /// in; a re-plan the same day must not book it again.
    private static let checkedInDayKey = "reminderCheckedInDay"

    /// Applies the current settings: asks for permission if needed, then
    /// replaces every pending daily notification with a fresh plan (or
    /// removes them all if disabled).
    /// Returns false if the user has denied notification permission.
    @discardableResult
    static func sync(enabled: Bool, windowStart: Int, windowEnd: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let today = LocalDay.string()
        let lastPlanned = UserDefaults.standard.string(forKey: lastPlannedDayKey) ?? ""
        let todayStillPending = await pendingDays(in: center).contains(today)
        await removeAll(from: center)
        guard enabled else { return true }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }

        // Today is planned again only if nothing has fired yet: either its
        // request was still pending, or it was never booked at all. Booking it
        // after the notification already went out would nudge twice.
        let includeToday = todayStillPending || lastPlanned < today
        await book(after: includeToday ? "" : today, windowStart: windowStart, windowEnd: windowEnd, in: center)
        return true
    }

    /// Extends the plan out to `horizonDays` again, using the saved settings.
    /// Never prompts: if permission was never granted, or the reminder is off,
    /// nothing happens. Called on every foreground.
    static func topUp() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: configuredKey), defaults.bool(forKey: enabledKey) else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        // An install from before the window existed still carries the single
        // repeating request; left in place it would fire beside the new one.
        center.removePendingNotificationRequests(withIdentifiers: [legacyRequestId])
        await book(
            after: defaults.string(forKey: lastPlannedDayKey) ?? "",
            windowStart: window(defaults, key: windowStartKey, fallback: defaultWindowStart),
            windowEnd: window(defaults, key: windowEndKey, fallback: defaultWindowEnd),
            in: center
        )
    }

    /// Drops today's pending reminder — the user has already checked in, so
    /// "check in with your mood for today" would just be noise. Tomorrow's
    /// booking is untouched.
    static func cancelToday() {
        let today = LocalDay.string()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestPrefix + today])
        UserDefaults.standard.set(today, forKey: checkedInDayKey)
    }

    /// Books one request for every day from today through the horizon whose
    /// day key sorts after `lastDone`, each at a random minute inside the
    /// window. Today's slot is drawn from what is left of the window; if the
    /// window has already closed, today gets nothing.
    private static func book(
        after lastDone: String, windowStart: Int, windowEnd: Int, in center: UNUserNotificationCenter
    ) async {
        let calendar = Calendar.current
        let now = Date.now
        let clock = calendar.dateComponents([.hour, .minute], from: now)
        // Leave a minute so today's trigger is never already in the past.
        let minutesElapsedToday = (clock.hour ?? 0) * 60 + (clock.minute ?? 0) + 1

        let content = UNMutableNotificationContent()
        content.title = "How are you?"
        content.body = "Check in with your mood for today."
        content.sound = .default

        let checkedInDay = UserDefaults.standard.string(forKey: checkedInDayKey)
        var lastDay = lastDone
        for offset in 0..<horizonDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let day = LocalDay.string(for: date)
            guard day > lastDone else { continue }
            lastDay = max(lastDay, day)
            // Already checked in today — nothing left to remind about.
            guard day != checkedInDay else { continue }

            let earliest = offset == 0 ? max(windowStart, minutesElapsedToday) : windowStart
            guard earliest <= windowEnd else { continue }
            let minute = Int.random(in: earliest...windowEnd)

            var time = calendar.dateComponents([.year, .month, .day], from: date)
            time.hour = minute / 60
            time.minute = minute % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: false)
            let request = UNNotificationRequest(identifier: requestPrefix + day, content: content, trigger: trigger)
            try? await center.add(request)
        }
        UserDefaults.standard.set(lastDay, forKey: lastPlannedDayKey)
    }

    private static func pendingDays(in center: UNUserNotificationCenter) async -> Set<String> {
        let ids = await center.pendingNotificationRequests().map(\.identifier)
        return Set(ids.filter { $0.hasPrefix(requestPrefix) }.map { String($0.dropFirst(requestPrefix.count)) })
    }

    private static func removeAll(from center: UNUserNotificationCenter) async {
        var ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(requestPrefix) }
        ids.append(legacyRequestId)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        UserDefaults.standard.removeObject(forKey: lastPlannedDayKey)
    }

    private static func window(_ defaults: UserDefaults, key: String, fallback: Int) -> Int {
        defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
    }
}
