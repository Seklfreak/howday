import SwiftUI
import WidgetKit

/// The lock screen, built around your own check-in. Circular: the unworn
/// ring with a "?" until you check in, then your emoji inside an arc of
/// the day that is left to change it. Rectangular: the six moods as
/// buttons until you check in — a tap saves without unlocking — then your
/// friends, latest first. Monochrome by iOS rule; the emoji is the colour.
struct CheckInWidget: Widget {
    static let kind = "CheckIn"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SkyProvider()) { entry in
            CheckInWidgetView(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("Check in")
        .description("Your mood today, and your friends' once you've checked in.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct CheckInWidgetView: View {
    let entry: SkyEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: CircularRing(snapshot: entry.snapshot, at: entry.date)
        default: RectangularStrip(snapshot: entry.snapshot)
        }
    }
}

/// Your ring: dashed and empty before the check-in, your emoji inside the
/// day's remaining arc after it.
private struct CircularRing: View {
    let snapshot: SkySnapshot
    let at: Date

    private var hoursLeft: Int {
        let midnight = Calendar.current.nextDate(
            after: at, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime
        ) ?? at
        return max(1, Int((midnight.timeIntervalSince(at) / 3600).rounded(.up)))
    }

    /// How much of the day is still ahead, as the arc's share of the ring.
    private var dayRemaining: Double {
        let start = Calendar.current.startOfDay(for: at)
        return max(0, min(1, 1 - at.timeIntervalSince(start) / 86_400))
    }

    var body: some View {
        ZStack {
            if let mine = snapshot.mine, snapshot.state == .ready {
                Circle().stroke(.white.opacity(0.25), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: dayRemaining)
                    .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(mine).font(.system(size: 24))
                    Text("\(hoursLeft) H LEFT")
                        .font(.system(size: 7, weight: .heavy, design: .rounded))
                        .tracking(0.3)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your mood today: \(mine); \(hoursLeft) hours left to change it")
            } else {
                Circle()
                    .stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [3, 4.5]))
                Text("?")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .accessibilityLabel("Not checked in yet")
            }
        }
        .padding(3)
        .widgetAccentable()
    }
}

/// The picker before your check-in, your friends after it.
private struct RectangularStrip: View {
    let snapshot: SkySnapshot

    var body: some View {
        switch snapshot.state {
        case .signedOut:
            Text("Open Howday to sign in").font(.system(size: 12, weight: .semibold, design: .rounded))
        case .failed:
            Text("Couldn't reach Howday").font(.system(size: 12, weight: .semibold, design: .rounded))
        case .ready where snapshot.mine == nil:
            picker
        case .ready:
            friends
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("How are you today?")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
            HStack(spacing: 4) {
                ForEach(snapshot.choices, id: \.self) { choice in
                    Button(intent: CheckInIntent(emoji: choice)) {
                        Text(choice)
                            .font(.system(size: 17))
                            .frame(width: 24, height: 24)
                            .overlay {
                                Circle().strokeBorder(
                                    .white.opacity(0.35),
                                    style: StrokeStyle(lineWidth: 1.2, dash: choice == snapshot.wildcard ? [2.5, 2.5] : [])
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(choice) mood")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var friends: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FRIENDS")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.7))
            if snapshot.friends.isEmpty {
                Text("No friends on Howday yet")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(snapshot.friends.prefix(5)) { friend in
                        VStack(spacing: 2) {
                            if let emoji = friend.emoji {
                                Text(emoji)
                                    .font(.system(size: 16))
                                    .frame(width: 24, height: 24)
                                    .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5) }
                            } else {
                                Circle()
                                    .strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
                                    .frame(width: 24, height: 24)
                            }
                            Text(friend.name)
                                .font(.system(size: 7, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(friend.isIn ? 0.9 : 0.5))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(minWidth: 28, maxWidth: 40)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(friend.isIn ? "\(friend.name), \(friend.emoji ?? "")" : "\(friend.name), not yet")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
