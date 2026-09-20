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
        // A friend's check-in is exactly what the widget shows: refresh it
        // now rather than at the next half-hour tick.
        WidgetCenter.shared.reloadAllTimelines()
        contentHandler(content)
    }

    /// iOS gives the extension about 30 seconds; a file read never gets
    /// near that, but the contract is to hand back *something*.
    override func serviceExtensionTimeWillExpire() {
        if let bestAttempt { contentHandler?(bestAttempt) }
    }
}
