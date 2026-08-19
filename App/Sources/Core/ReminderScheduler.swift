import Foundation
import UserNotifications

/// Owns the single daily "how are you?" local notification. Everything is
/// on-device — no APNs, no server involvement.
enum ReminderScheduler {
    private static let requestId = "daily-checkin"

    /// Applies the current settings: asks for permission if needed, then
    /// replaces the pending daily notification (or removes it if disabled).
    /// Returns false if the user has denied notification permission.
    @discardableResult
    static func sync(enabled: Bool, hour: Int, minute: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestId])
        guard enabled else { return true }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = "How are you?"
        content.body = "Check in with your mood for today."
        content.sound = .default

        var time = DateComponents()
        time.hour = hour
        time.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)
        try? await center.add(request)
        return true
    }
}
