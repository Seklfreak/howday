import Foundation
import OSLog
import UserNotifications
import WidgetKit

/// Rewrites a friend push's generic body into a named one. The payload's
/// `sender_hash` is looked up in the name map the app maintains in the App
/// Group container; `kind` picks the wording. Anything missing — no hash,
/// a sender not in the map, no map at all — leaves the server's generic
/// text as it is, which is what shipped before this extension existed.
final class NotificationService: UNNotificationServiceExtension {
    private static let log = Logger(subsystem: "dev.winktech.moodring", category: "notifications")

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttempt = content
        let userInfo = request.content.userInfo
        // Outcome only — never the name or the hash.
        if let hash = userInfo["sender_hash"] as? String {
            if let name = NameMap.name(for: hash) {
                content.body = PushText.body(name: name, kind: userInfo["kind"] as? String)
                Self.log.info("sender named")
            } else {
                Self.log.info("sender not in the name map; generic body kept")
            }
        } else {
            Self.log.info("no sender hash in payload; generic body kept")
        }
        // A friend's check-in is exactly what the widget shows, and the
        // push carries the mood itself, so the sky can be written here and
        // drawn from the App Group with no round trip at all. That matters
        // most on the lock screen, which is looked at while the phone is
        // still locked — precisely the window a fetch spends waking the
        // radio. Anything the patch cannot answer for (no mood in the
        // payload, a sender who is not on the stored sky, yesterday's sky)
        // falls back to marking it behind the truth, which is what every
        // push did before.
        switch storedSkyPatch(userInfo) {
        case .written:
            WidgetCenter.shared.reloadAllTimelines()
        case .alreadyShown:
            // The sky is already right — whoever read it reloaded then.
            break
        case .cannotAnswer:
            SkySnapshotStore.invalidate()
            WidgetCenter.shared.reloadAllTimelines()
        }
        // Calling the handler is what lets iOS tear this process down, and
        // the reload is a message to the widget daemon that has to leave
        // first. A fifth of a second is imperceptible on a banner and is
        // the difference between a request sent and one lost with us.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { contentHandler(content) }
    }

    /// The sender's own mood, written into the stored sky. The timestamp is
    /// the device's, not the server's: a push lands within a second or two
    /// of the check-in it announces, and the only thing that reads it is the
    /// ordering of a handful of friends.
    private func storedSkyPatch(_ userInfo: [AnyHashable: Any]) -> SkySnapshot.Patch {
        // Both or neither: a push from before the server sent them, and a
        // join push, carry no mood and get the old behaviour.
        guard let emoji = userInfo["emoji"] as? String,
              let raw = userInfo["sender_id"] as? String,
              let sender = UUID(uuidString: raw) else { return .cannotAnswer }
        let patch = SkySnapshotStore.applyCheckin(by: sender, emoji: emoji)
        // Outcome only — never the mood, the name or the hash.
        switch patch {
        case .written: Self.log.info("sky written from payload")
        case .alreadyShown: Self.log.info("sky already showed it")
        case .cannotAnswer: Self.log.info("sky could not answer; marked behind")
        }
        return patch
    }

    /// iOS gives the extension about 30 seconds; a file read never gets
    /// near that, but the contract is to hand back *something*.
    override func serviceExtensionTimeWillExpire() {
        if let bestAttempt { contentHandler?(bestAttempt) }
    }
}
