import Foundation
import WidgetKit

/// The widget extension's half of the analytics. No queue: a widget process
/// is short-lived and may be killed the moment its timeline is handed back,
/// so an event is either sent while the work is still happening or dropped.
/// Losing one census ping is harmless; the next refresh sends another.
///
/// Disabled in Debug, mirroring the app, and a no-op whenever the widget's
/// own Info.plist has no Umami values — which is what CI and simulator
/// builds get from the placeholder xcconfig.
enum WidgetAnalytics {
    static func track(_ event: String, _ data: [String: String] = [:], path: String, title: String) async {
        #if !DEBUG
        guard let config = Umami.config() else { return }
        let payload = Umami.payload(config: config, path: path, title: title, name: event, data: data)
        _ = await Umami.post(payload, config: config)
        #endif
    }

    /// Which widgets a person actually has, sent at most once a day per
    /// widget and size. Without it there is no denominator: taps by source
    /// say which widget gets used, this says which widget is installed.
    /// Throttled through the App Group so all of a day's timeline
    /// rebuilds — a dozen or more — count once.
    static func widgetActive(kind: String, family: WidgetFamily, day: String = LocalDay.string()) async {
        let source = family.source(kind: kind)
        let key = "analytics.widgetActive.\(kind).\(source.rawValue)"
        let defaults = UserDefaults(suiteName: NameMap.appGroup) ?? .standard
        guard defaults.string(forKey: key) != day else { return }
        // Written before the send, not after: a failed request that retried
        // on every rebuild would report one widget a dozen times a day.
        defaults.set(day, forKey: key)
        await track(
            "widget_active", ["source": source.rawValue],
            path: "/widget/\(source.rawValue)", title: "Widget"
        )
    }
}

extension WidgetFamily {
    /// The source a tap on this widget reports. `kind` separates the two
    /// widgets that share the accessory families.
    func source(kind: String) -> WidgetSource {
        switch self {
        case .systemSmall: .skySmall
        case .systemMedium: .skyMedium
        case .systemLarge: .skyLarge
        case .accessoryCircular: .lockCircular
        case .accessoryRectangular: .lockRectangular
        default: kind == CheckInWidget.kind ? .lockRectangular : .skyMedium
        }
    }
}
