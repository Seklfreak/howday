import SwiftUI
import WidgetKit

@main
struct HowdayWidgetBundle: WidgetBundle {
    var body: some Widget {
        FriendsSkyWidget()
        CheckInWidget()
        if #available(iOS 18.0, *) {
            CheckInControl()
        }
    }
}

/// Your friends' moods afloat. Small and medium scatter the emoji, large
/// lays them out along the day. Before your own check-in the same sky is
/// question marks — the widget keeps the app's gate.
struct FriendsSkyWidget: Widget {
    static let kind = "FriendsSky"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SkyProvider(kind: Self.kind)) { entry in
            SkyWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    SkyBackground(snapshot: entry.snapshot)
                }
        }
        .configurationDisplayName("Friends today")
        .description("Your friends' emoji, once you've checked in.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct SkyEntry: TimelineEntry {
    let date: Date
    let snapshot: SkySnapshot

    /// The drift step this entry shows; see `SkyLayout.phase(at:)`.
    var phase: Int { SkyLayout.phase(at: date) }
}

struct SkyProvider: TimelineProvider {
    /// Which widget this provider serves. Only analytics needs it: both
    /// widgets read the same board, but a census has to say which of them
    /// a person actually has.
    let kind: String

    func placeholder(in context: Context) -> SkyEntry {
        SkyEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SkyEntry) -> Void) {
        if context.isPreview {
            completion(SkyEntry(date: .now, snapshot: .placeholder))
            return
        }
        Task { completion(SkyEntry(date: .now, snapshot: await SkyRepository.load())) }
    }

    /// One board read, shown as an entry every five minutes for the next
    /// two hours: the same snapshot, the emoji drifted a little further
    /// each step (WidgetKit animates the change between entries, which is
    /// as close to floating as a widget gets). The timeline then rebuilds
    /// with a fresh read — or at midnight, when the day and its sky
    /// change. Two hours, not thirty minutes: every rebuild spends the
    /// refresh budget iOS gives a widget for the day (a few dozen), and
    /// past it iOS delays reloads until the widget sits on a stale entry
    /// for hours. The app and the notification extension reload it
    /// whenever something actually changes, which is what keeps it fresh.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SkyEntry>) -> Void) {
        Task {
            let now = Date.now
            let snapshot = await SkyRepository.load()
            await WidgetAnalytics.widgetActive(kind: kind, family: context.family)
            let midnight = Calendar.current.nextDate(
                after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime
            ) ?? now.addingTimeInterval(30 * 60)
            // Entries land on step boundaries so a rebuild at any moment
            // continues the same drift; the first one is "now".
            let step: TimeInterval = 300
            let firstBoundary = (now.timeIntervalSince1970 / step).rounded(.up) * step
            var dates = [now]
            var next = Date(timeIntervalSince1970: firstBoundary)
            // Two hours of drift after a clean read. After a failed one —
            // or a fall back to the last good sky — come back in fifteen
            // minutes instead of committing the error to the whole window.
            let fresh = snapshot.state == .ready && !snapshot.isStale
            let horizon = now.addingTimeInterval(fresh ? 2 * 60 * 60 : 15 * 60)
            while next < min(horizon, midnight) {
                dates.append(next)
                next = next.addingTimeInterval(step)
            }
            let entries = dates.map { SkyEntry(date: $0, snapshot: snapshot) }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }
}

// MARK: - Views

struct SkyWidgetView: View {
    let entry: SkyEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch entry.snapshot.state {
            case .signedOut:
                message("Open Howday to sign in")
            case .failed:
                message("Couldn't reach Howday")
            case .ready where entry.snapshot.friends.isEmpty:
                message("No friends on Howday yet")
            case .ready:
                switch family {
                case .systemLarge:
                    LargeSky(snapshot: entry.snapshot, phase: entry.phase)
                default:
                    ScatteredSky(snapshot: entry.snapshot, phase: entry.phase, showsNames: family == .systemMedium)
                }
            }
        }
        // What makes a tap attributable: without it the widget opens the
        // app with nothing to say about where the person came from.
        .widgetURL(family.source(kind: FriendsSkyWidget.kind).openURL)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding()
    }
}

/// The small and medium widgets. Locked (no check-in of your own yet), the
/// emoji become question marks and a caption says why.
private struct ScatteredSky: View {
    let snapshot: SkySnapshot
    let phase: Int
    let showsNames: Bool

    private var locked: Bool { snapshot.mine == nil }

    var body: some View {
        GeometryReader { proxy in
            let layout = SkyLayout.scattered(
                snapshot.friends, in: proxy.size, day: snapshot.day, phase: phase,
                inset: 10, topInset: showsNames ? 2 : 0, bottomInset: locked ? 30 : (showsNames ? 12 : 0),
                labelAllowance: showsNames && !locked ? 12 : 0
            )
            ZStack {
                ForEach(layout.placements, id: \.friend.id) { placement in
                    FriendMark(placement: placement, locked: locked, showsName: showsNames && !locked)
                        .position(placement.center)
                }
                if locked {
                    VStack {
                        Spacer()
                        Text("\(snapshot.friendsIn) friends are in · check in to see")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.1), in: Capsule())
                            .padding(.bottom, 10)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            // The glide from one step's positions to the next.
            .animation(.easeInOut(duration: 1.5), value: phase)
        }
    }
}

/// The large widget: the day's sky, morning on the left.
private struct LargeSky: View {
    let snapshot: SkySnapshot
    let phase: Int

    private var locked: Bool { snapshot.mine == nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                // "Updated 12:03" is diagnostic: it says when the widget last
                // read the board, which is the only way to tell a stale sky
                // from a quiet day.
                Text(
                    "\(Date.now.formatted(.dateTime.weekday(.wide))) · \(snapshot.friendsIn) of \(snapshot.friends.count) friends in"
                        + " · updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))"
                )
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if let mine = snapshot.mine {
                    HStack(spacing: 4) {
                        Text(mine).font(.system(size: 14))
                        Text("You")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            // Explicit: a widget's default text colour follows
                            // the home screen's rendering, which made this
                            // black on the dark sky.
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.1), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            GeometryReader { proxy in
                let layout = SkyLayout.byTime(
                    snapshot.friends, in: proxy.size, day: snapshot.day, phase: phase, topInset: 8, bottomInset: 8,
                    labelAllowance: locked ? 0 : 12
                )
                ZStack {
                    ForEach(layout.placements, id: \.friend.id) { placement in
                        FriendMark(placement: placement, locked: locked, showsName: !locked)
                            .position(placement.center)
                    }
                    if locked {
                        Text("\(snapshot.friendsIn) friends are in · check in to see")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                }
                .animation(.easeInOut(duration: 1.5), value: phase)
            }
            VStack(spacing: 5) {
                Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
                HStack {
                    Text("morning"); Spacer(); Text("midday"); Spacer(); Text("afternoon"); Spacer(); Text("evening")
                }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}

/// One friend: an emoji glowing in its mood's colour, a "?" while locked,
/// or a faint ring when they have not checked in.
private struct FriendMark: View {
    let placement: SkyLayout.Placement
    let locked: Bool
    let showsName: Bool

    private var theme: MoodTheme { MoodTheme.forEmoji(placement.friend.emoji) }

    var body: some View {
        VStack(spacing: 1) {
            if let emoji = placement.friend.emoji {
                if locked {
                    Text("?")
                        .font(.system(size: placement.diameter * 0.55, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: placement.diameter, height: placement.diameter)
                        .background(Circle().fill(RadialGradient(
                            colors: [MoodTheme.neutral.accent.opacity(0.18), .clear],
                            center: .center, startRadius: 0, endRadius: placement.diameter / 2
                        )))
                } else {
                    Text(emoji)
                        .font(.system(size: placement.diameter * 0.84))
                        .frame(width: placement.diameter, height: placement.diameter)
                        .background(Circle().fill(RadialGradient(
                            colors: [theme.accent.opacity(0.25), .clear],
                            center: .center, startRadius: 0, endRadius: placement.diameter / 2
                        )))
                        .shadow(color: theme.accent.opacity(0.6), radius: placement.diameter / 5)
                }
            } else {
                Circle()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 2)
                    .frame(width: placement.diameter, height: placement.diameter)
            }
            if showsName {
                Text(placement.friend.name)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(placement.friend.isIn ? 0.72 : 0.4))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard placement.friend.isIn else { return "\(placement.friend.name), not yet" }
        if locked { return "\(placement.friend.name) has checked in" }
        return "\(placement.friend.name), \(placement.friend.emoji ?? "")"
    }
}

/// The liquid-crystal ground, tinted by the three most recent friends'
/// moods — a golden sky is a good day among your friends, a blue one a
/// rough day. Pearl-neutral while locked or empty.
private struct SkyBackground: View {
    let snapshot: SkySnapshot

    private var themes: [MoodTheme] {
        guard snapshot.mine != nil else { return [.neutral, .neutral, .neutral] }
        let recent = snapshot.friends.compactMap(\.emoji).prefix(3).map { MoodTheme.forEmoji($0) }
        return Array(recent) + Array(repeating: MoodTheme.neutral, count: max(0, 3 - recent.count))
    }

    var body: some View {
        let mix = themes
        ZStack {
            MoodTheme.neutral.deep
            bloom(mix[0].glow.opacity(0.55), center: .init(x: 0.18, y: 0.08), radius: 0.75)
            bloom(mix[1].accent.opacity(0.28), center: .init(x: 0.88, y: 0.30), radius: 0.65)
            bloom(mix[2].glow.opacity(0.40), center: .init(x: 0.50, y: 1.05), radius: 0.80)
        }
    }

    private func bloom(_ color: Color, center: UnitPoint, radius: Double) -> some View {
        Rectangle().fill(EllipticalGradient(
            colors: [color, .clear], center: center, startRadiusFraction: 0, endRadiusFraction: radius
        ))
    }
}
