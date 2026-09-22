import Foundation
import UIKit

/// The parts of the Umami client the app and its extensions both need: who
/// the visitor is, what a payload looks like, and how it is posted. The
/// app's `Analytics` adds a queue and screen state on top; the widget
/// extension fires one event at a time and awaits it.
///
/// Deliberately incurious, as in the app: the visitor id is a random UUID
/// per install, never the Supabase user id, and no mood, name, phone number
/// or hash is ever sent.
enum Umami {
    /// The domain the site is registered under in Umami. Not a real host —
    /// it keeps app traffic apart from the websites on the same instance.
    static let hostname = "howday.ios"

    struct Config {
        let endpoint: URL
        let websiteID: String
        let userAgent: String
    }

    /// Reads the Info.plist of whichever bundle is asking — the app's for
    /// the app, the appex's for an extension, which is why the widget
    /// target carries the same two keys. Nil (a no-op) unless both are set,
    /// exactly as CI and simulator builds get from the placeholder xcconfig.
    static func config(in bundle: Bundle = .main) -> Config? {
        guard let raw = bundle.object(forInfoDictionaryKey: "UMAMI_URL") as? String,
              let base = URL(string: raw), base.host != nil,
              let website = bundle.object(forInfoDictionaryKey: "UMAMI_WEBSITE_ID") as? String,
              !website.isEmpty else { return nil }
        return Config(
            endpoint: base.appendingPathComponent("api/send"),
            websiteID: website,
            userAgent: userAgent(for: bundle)
        )
    }

    /// Umami rejects a request with no User-Agent outright, and answers one
    /// its bot filter matches with a 200 that stores nothing — so this has
    /// to read as a browser. It is also where Umami reads the OS and device
    /// from, so it must not be reduced to "Howday/1.0".
    private static func userAgent(for bundle: Bundle) -> String {
        let os = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(os) like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Howday/\(version)"
    }

    /// Shared with the extensions through the App Group: an event sent by
    /// the widget has to count as the same visitor as one sent by the app,
    /// or every widget user looks like a second person.
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: NameMap.appGroup) ?? .standard
    }

    private static let visitorKey = "analytics.visitorId"
    private static let screenKey = "analytics.screenSize"

    /// Random per install, kept so returning visitors are countable, and
    /// gone with the app. A UUID string is well inside Umami's 50-character
    /// limit. An install from before the group was shared still has its id
    /// in the app's own defaults — adopt it rather than minting a second one
    /// and splitting that person's history in two.
    static var visitorID: String {
        let shared = defaults
        if let existing = shared.string(forKey: visitorKey) { return existing }
        let inherited = UserDefaults.standard.string(forKey: visitorKey)
        let id = inherited ?? UUID().uuidString
        shared.set(id, forKey: visitorKey)
        return id
    }

    /// The app measures the window once and leaves it here; an extension has
    /// no window to measure and would otherwise report 0x0 and skew the
    /// device breakdown. The fallback is a current iPhone in points.
    static var screenSize: String {
        get { defaults.string(forKey: screenKey) ?? "393x852" }
        set { defaults.set(newValue, forKey: screenKey) }
    }

    /// The JSON Umami's own web tracker would have posted. An event without
    /// a `name` is what Umami stores as a pageview.
    static func payload(
        config: Config, path: String, title: String, name: String?, data: [String: String]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "website": config.websiteID,
            "hostname": hostname,
            "url": path,
            "title": title,
            "language": Locale.preferredLanguages.first ?? "en-US",
            "screen": screenSize,
            "id": visitorID,
        ]
        if let name { payload["name"] = name }
        if !data.isEmpty { payload["data"] = data }
        return payload
    }

    /// Posts one event. `true` means Umami took it; `false` means the caller
    /// should keep it for the next attempt.
    static func post(_ payload: [String: Any], config: Config) async -> Bool {
        guard let body = try? JSONSerialization.data(
            withJSONObject: ["type": "event", "payload": payload]
        ) else { return true }  // Unencodable: dropping it is the only option.
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        // A widget's `getTimeline` awaits this before it hands the timeline
        // back, and the default request timeout is sixty seconds: a census
        // ping must never be the thing holding a refresh up. The app keeps a
        // failure for its next attempt; the widget drops it and sends
        // another on the next rebuild.
        request.timeoutInterval = 5
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return ((response as? HTTPURLResponse)?.statusCode ?? 500) < 400
    }
}

/// Where a tap or a check-in came from. The string is what the dashboard
/// groups by, so these values are effectively schema: change one and the
/// reports split at that date.
enum WidgetSource: String {
    case skySmall = "sky-small"
    case skyMedium = "sky-medium"
    case skyLarge = "sky-large"
    case lockCircular = "lock-circular"
    case lockRectangular = "lock-rectangular"
    case control = "control-center"
    /// Not a widget: the app's own picker, so the two are comparable.
    case app

    /// `howday://open?source=…` — what a widget hands the app when tapped,
    /// and the only way to tell which widget a session came from.
    var openURL: URL? { URL(string: "howday://open?source=\(rawValue)") }

    static func from(openURL url: URL) -> WidgetSource? {
        guard url.scheme == "howday", url.host == "open",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "source" })?.value else { return nil }
        return WidgetSource(rawValue: value)
    }
}
