import Foundation
import UIKit

/// First-party analytics against the self-hosted Umami instance. Umami's
/// `/api/send` accepts exactly the JSON its web tracker would have posted, so
/// a native app can speak it directly — no SDK, no third party in the path.
///
/// Deliberately incurious: the visitor id is a random UUID minted per install
/// and forgotten when the app is deleted — never the Supabase user id — and no
/// mood, name, phone number or hash is ever sent. Nothing here touches the
/// IDFA, so the app needs no tracking prompt.
@MainActor
enum Analytics {
    /// Screens as Umami sees them: `rawValue` is the path, `title` the label
    /// in the dashboard. Picker and board are the same SwiftUI view in its two
    /// states — before today's check-in and after — which is the one funnel
    /// step worth seeing.
    enum Screen: String {
        case signIn = "sign-in"
        case onboarding
        case notifications = "onboarding-notifications"
        case home
        case board
        case history
        case settings
        case reminder

        var title: String {
            switch self {
            case .signIn: "Sign in"
            case .onboarding: "Onboarding"
            case .notifications: "Notifications"
            case .home: "Mood picker"
            case .board: "Friends board"
            case .history: "History"
            case .settings: "Settings"
            case .reminder: "Daily reminder"
            }
        }
    }

    /// The domain the site is registered under in Umami. Not a real host — it
    /// just keeps app traffic apart from the websites on the same instance.
    /// Matches the domain the site is declared with in winkcloud. Renaming
    /// it does not move any data — events are filed by website id — it only
    /// means reports show two hostnames across the rename.
    private static let hostname = "howday.ios"
    /// A long offline stretch drops the oldest events rather than growing.
    private static let queueLimit = 50

    private static var endpoint: URL?
    private static var websiteID = ""
    private static var userAgent = ""
    private static var currentPath = "/"
    private static var currentTitle = ""
    /// SwiftUI calls `onAppear` more than once on a NavigationStack root when
    /// a pushed view pops — returning from History counted the board twice.
    /// A screen repeating within this window is that bounce, not a visit.
    private static let repeatWindow: TimeInterval = 2
    private static var lastScreenAt: Date?
    private static var pending: [[String: Any]] = []
    private static var isSending = false
    private static var cachedScreenSize: String?

    /// Random per install, kept so returning visitors are countable, and gone
    /// with the app. A UUID string is well inside Umami's 50-character limit.
    private static let visitorID: String = {
        let key = "analytics.visitorId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()

    /// A no-op unless both values are configured — CI and simulator builds run
    /// from the placeholder xcconfig, exactly as they do for Sentry's DSN.
    static func configure() {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "UMAMI_URL") as? String,
              let base = URL(string: raw), base.host != nil,
              let website = Bundle.main.object(forInfoDictionaryKey: "UMAMI_WEBSITE_ID") as? String,
              !website.isEmpty else { return }
        endpoint = base.appendingPathComponent("api/send")
        websiteID = website
        userAgent = browserUserAgent()
        // Anything stranded by a dead network gets another chance on return.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in send() }
        }
    }

    /// A pageview. Also fixes the path that subsequent `track` calls carry.
    static func screen(_ screen: Screen) {
        let path = "/\(screen.rawValue)"
        // Deliberately not "same as last" alone: a genuine second visit to the
        // screen you were just on is still worth counting, minutes later.
        if path == currentPath, let lastScreenAt, Date().timeIntervalSince(lastScreenAt) < repeatWindow {
            return
        }
        currentPath = path
        currentTitle = screen.title
        lastScreenAt = Date()
        queue(name: nil, data: [:])
    }

    /// An action on the current screen. Keep `data` free of anything personal:
    /// no emoji, no names, no identifiers.
    static func track(_ event: String, _ data: [String: String] = [:]) {
        queue(name: event, data: data)
    }

    private static func queue(name: String?, data: [String: String]) {
        guard endpoint != nil else { return }
        var payload: [String: Any] = [
            "website": websiteID,
            "hostname": hostname,
            "url": currentPath,
            "title": currentTitle,
            "language": Locale.preferredLanguages.first ?? "en-US",
            "screen": screenSize,
            "id": visitorID,
        ]
        // An event without a name is what Umami stores as a pageview.
        if let name { payload["name"] = name }
        if !data.isEmpty { payload["data"] = data }

        pending.append(payload)
        if pending.count > queueLimit { pending.removeFirst(pending.count - queueLimit) }
        send()
    }

    /// Drains the queue one event at a time, in order; a failure leaves the
    /// event in place for the next event or the next foreground to retry.
    private static func send() {
        guard let endpoint, !isSending, let next = pending.first else { return }
        guard let body = try? JSONSerialization.data(withJSONObject: ["type": "event", "payload": next]) else {
            pending.removeFirst()
            send()
            return
        }
        isSending = true

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { _, response, error in
            let accepted = error == nil && ((response as? HTTPURLResponse)?.statusCode ?? 500) < 400
            Task { @MainActor in
                isSending = false
                guard accepted, !pending.isEmpty else { return }
                pending.removeFirst()
                send()
            }
        }.resume()
    }

    /// Umami rejects a request with no User-Agent outright, and answers one
    /// its bot filter matches with a 200 that stores nothing — so this has to
    /// read as a browser. It is also where Umami reads the OS and device from.
    private static func browserUserAgent() -> String {
        let os = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(os) like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Howday/\(version)"
    }

    /// Points, mirroring the CSS pixels the web tracker reports. Read lazily:
    /// at app init there is no window scene to measure yet.
    private static var screenSize: String {
        if let cachedScreenSize { return cachedScreenSize }
        let size = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first?.bounds.size }
            .first ?? .zero
        let value = "\(Int(size.width))x\(Int(size.height))"
        if size != .zero { cachedScreenSize = value }
        return value
    }
}
