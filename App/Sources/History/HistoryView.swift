import SwiftUI

struct HistoryView: View {
    @State private var monthAnchor: Date = .now
    @State private var checkinsByDay: [String: Checkin] = [:]
    @State private var selected: Checkin?
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
    /// Which way the grid should slide. Set before the month changes so the
    /// transition matches the direction of travel rather than always
    /// arriving from the same side.
    @State private var slideForward = true

    private var calendar: Calendar { .current }
    private var cellHeight: CGFloat { DayCell.baseHeight * TypeScale.clamp(scale) }

    // Pushed from HomeView's toolbar, so it rides the home NavigationStack
    // rather than owning one.
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader
                // Seven columns cannot hold accessibility-size digits: at
                // the largest setting every two-digit day became "…". The
                // grid follows the text size up to the last regular step
                // and stops there; the cells still grow (TypeScale).
                Group {
                    weekdayHeader
                    dayGrid
                        .id(monthKey)
                        .transition(.asymmetric(
                            insertion: .move(edge: slideForward ? .trailing : .leading),
                            removal: .move(edge: slideForward ? .leading : .trailing)
                        ))
                        // The outgoing and incoming months overlap mid-slide;
                        // without this they paint over the header and the
                        // screen's edges.
                        .clipped()
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            .padding()
        }
        .background {
            // Neutral by design: a month holds many moods — the cells carry
            // the color, the backdrop stays the unworn ring.
            MoodBackground(theme: .neutral)
        }
        // Swipe to flip through months, the way a calendar does. Simultaneous
        // rather than exclusive: the scroll view still owns vertical drags,
        // which is why this only acts on a clearly horizontal one. The
        // chevrons stay — a gesture is not discoverable, and VoiceOver has
        // no way to perform this one.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                    step(months: drag.translation.width < 0 ? 1 : -1)
                }
        )
        .sensoryFeedback(.selection, trigger: monthKey)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("History")
        .onAppear { Analytics.screen(.history) }
        .task(id: monthKey) { await load() }
        .sheet(item: $selected) { checkin in
            CheckinDetailSheet(checkin: checkin)
                .presentationDetents([.height(220)])
        }
    }

    // MARK: month math

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: monthAnchor)) ?? monthAnchor
    }

    private var monthKey: String { LocalDay.string(for: monthStart) }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
    }

    /// Empty cells before day 1, honoring the locale's first weekday.
    private var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(monthAnchor, equalTo: .now, toGranularity: .month)
    }

    private func date(day: Int) -> Date {
        calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
    }

    // MARK: subviews

    /// Moves by whole months, and is the only way the month changes — the
    /// chevrons and the swipe share it so both animate the same way and
    /// both stop at the current month. There is nothing to show ahead of
    /// today, and a forward swipe into an empty grid reads as a bug.
    private func step(months: Int) {
        guard months < 0 || !isCurrentMonth,
              let moved = calendar.date(byAdding: .month, value: months, to: monthAnchor) else { return }
        slideForward = months > 0
        withAnimation(.easeInOut(duration: 0.25)) { monthAnchor = moved }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                step(months: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(monthStart.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .contentTransition(.numericText())
            Spacer()
            Button {
                step(months: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next month")
            .disabled(isCurrentMonth)
        }
        .padding(.horizontal, 4)
    }

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
        return HStack {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            // Negative ids: LazyVGrid flattens identity across all its
            // ForEach children, so blank ids overlapping day numbers (1...)
            // silently drop those day cells.
            ForEach(-leadingBlanks..<0, id: \.self) { _ in
                Color.clear.frame(height: cellHeight)
            }
            ForEach(1...daysInMonth, id: \.self) { day in
                let checkin = checkinsByDay[LocalDay.string(for: date(day: day))]
                DayCell(day: day, checkin: checkin, isToday: calendar.isDateInToday(date(day: day)))
                    .onTapGesture {
                        if let checkin { selected = checkin }
                    }
            }
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            let first = LocalDay.string(for: monthStart)
            let last = LocalDay.string(for: date(day: daysInMonth))
            let rows = try await withSkewRetry { try await CheckinRepository().mine(from: first, to: last) }
            checkinsByDay = Dictionary(uniqueKeysWithValues: rows.map { ($0.day, $0) })
        } catch {
            // Leaving the tab cancels the .task mid-request; don't show
            // that as an error — reappearing restarts the load anyway.
            guard !error.isCancellation else { return }
            errorMessage = error.report("history.load")
        }
    }
}

private struct DayCell: View {
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

private struct CheckinDetailSheet: View {
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
