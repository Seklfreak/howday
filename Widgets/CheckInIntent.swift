import AppIntents
import Foundation
import Supabase
import WidgetKit

/// The lock-screen picker's tap: saves today's mood without opening the
/// app. Mirrors `CheckinRepository.saveToday` (which the widget can't link
/// — it sits behind Sentry tracing): the same upsert on (user_id, day),
/// always targeting the current local day, so it cannot backdate either.
///
/// No offline queue here: a save that fails leaves the widget as it was,
/// and the app's own picker is one unlock away. The app notices a
/// check-in made here on its next load and cancels the day's reminder.
struct CheckInIntent: AppIntent {
    static let title: LocalizedStringResource = "Check in"
    static let description = IntentDescription("Saves your mood for today.")

    @Parameter(title: "Mood")
    var emoji: String

    init() {
        emoji = "🙂"
    }

    init(emoji: String) {
        self.emoji = emoji
    }

    func perform() async throws -> some IntentResult {
        let userId = try await Supa.client.auth.session.user.id
        let payload = CheckInPayload(
            userId: userId, day: LocalDay.string(), emoji: emoji,
            updatedAt: Date.now.storedTimestamp
        )
        try await Supa.client
            .from("checkins")
            .upsert(payload, onConflict: "user_id,day", returning: .minimal)
            .execute()
        // The board this just changed has not been read back here, so the
        // stored sky must not stand in for the refresh that follows.
        SkySnapshotStore.invalidate()
        WidgetCenter.shared.reloadAllTimelines()
        // Counted the same way the app counts its own, so the two are
        // comparable; the emoji stays out of it, as everywhere else.
        await WidgetAnalytics.track(
            "checkin_saved", ["source": WidgetSource.lockRectangular.rawValue],
            path: "/widget/\(WidgetSource.lockRectangular.rawValue)", title: "Widget"
        )
        return .result()
    }
}

/// The upsert body, the same shape `CheckinRepository` sends.
private struct CheckInPayload: Encodable {
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
