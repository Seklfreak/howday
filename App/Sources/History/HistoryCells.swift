import SwiftUI

/// The two leaves of the history screen: one day in the month grid, and
/// the sheet a day opens. Split from `HistoryView` for file length.

struct DayCell: View {
    /// Cell height at the default text size.
    static let baseHeight: CGFloat = 40

    let day: Int
    let checkin: Checkin?
    let isToday: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    /// The day's mood colors — nil for days without a check-in, which stay
    /// a faint neutral so the month reads as a color story at arm's length.
    private var theme: MoodTheme? {
        checkin.map { MoodTheme.forEmoji($0.emoji) }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(theme?.accent.opacity(0.22) ?? .white.opacity(0.045))
            .frame(height: 40)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(theme?.accent.opacity(0.35) ?? .white.opacity(0.05), lineWidth: 1)
            }
            .overlay {
                if let checkin {
                    VStack(spacing: 0) {
                        Text("\(day)")
                            .font(.system(size: 9))
                            .fontWeight(isToday ? .bold : .regular)
                            .foregroundStyle(.secondary)
                        Text(checkin.emoji)
                            .font(.system(size: 17))
                    }
                } else {
                    Text("\(day)")
                        .font(.caption)
                        .fontWeight(isToday ? .bold : .regular)
                        .foregroundStyle(.secondary)
                }
            }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme?.accent ?? .primary, lineWidth: 1.5)
                }
            }
    }
}

struct CheckinDetailSheet: View {
    let checkin: Checkin

    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var theme: MoodTheme { MoodTheme.forEmoji(checkin.emoji) }

    /// "Wednesday, August 19" instead of the stored "2026-08-19" — with the
    /// month abbreviated at the accessibility sizes, where the sheet's
    /// fixed height leaves the full form one truncated line.
    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: checkin.day) else { return checkin.day }
        let month: Date.FormatStyle.Symbol.Month = dynamicTypeSize.isAccessibilitySize ? .abbreviated : .wide
        return date.formatted(.dateTime.weekday(.wide).month(month).day())
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(checkin.emoji)
                .font(.system(size: 44 * TypeScale.clamp(scale)))
                .frame(width: 84 * TypeScale.clamp(scale), height: 84 * TypeScale.clamp(scale))
                .background(Circle().fill(.white.opacity(0.07)))
                .overlay(Circle().strokeBorder(theme.accent, lineWidth: 3))
                .shadow(color: theme.accent.opacity(0.55), radius: 12)
            Text(dateText).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
        .presentationBackground(theme.deep)
    }
}
