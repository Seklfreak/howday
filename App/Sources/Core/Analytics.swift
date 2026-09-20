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

    /// A long offline stretch drops the oldest events rather than growing.
    private static let queueLimit = 50

    /// Endpoint, website id and user agent; nil until `configure`, which is
    /// also what makes every call below a no-op. Shared with the widget
    /// extension (see `Shared/Umami.swift`) so both report as one visitor.
    private static var config: Umami.Config?
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

    /// A no-op unless both values are configured — CI and simulator builds run
    /// from the placeholder xcconfig, exactly as they do for Sentry's DSN.
    static func configure() {
        guard let resolved = Umami.config() else { return }
        config = resolved
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
        guard let config else { return }
        rememberScreenSize()
        let payload = Umami.payload(
            config: config, path: currentPath, title: currentTitle, name: name, data: data
        )
        pending.append(payload)
        if pending.count > queueLimit { pending.removeFirst(pending.count - queueLimit) }
        send()
    }

    /// Drains the queue one event at a time, in order; a failure leaves the
    /// event in place for the next event or the next foreground to retry.
    private static func send() {
        guard let config, !isSending, let next = pending.first else { return }
        isSending = true
        Task { @MainActor in
            let accepted = await Umami.post(next, config: config)
            isSending = false
            guard accepted, !pending.isEmpty else { return }
            pending.removeFirst()
            send()
        }
    }

    /// Points, mirroring the CSS pixels the web tracker reports. Measured
    /// lazily and only once it is real: at app init there is no window scene
    /// yet, and writing the 0x0 that reads back would hand the extensions —
    /// which have no window of their own and take this value from the App
    /// Group — a device size that never existed.
    private static func rememberScreenSize() {
        guard cachedScreenSize == nil else { return }
        let size = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first?.bounds.size }
            .first ?? .zero
        guard size != .zero else { return }
        let value = "\(Int(size.width))x\(Int(size.height))"
        cachedScreenSize = value
        Umami.screenSize = value
    }
}
