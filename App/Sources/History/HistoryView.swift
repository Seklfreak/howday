import SwiftUI

struct HistoryView: View {
    /// Every month the sheet can reach: five years back through the current
    /// one, which is the last page because there is nothing ahead of today.
    /// The stack is lazy, so only the months on screen are ever built.
    @State private var months: [Date] = HistoryView.monthWindow()
    /// Which month the scroll view has settled on. Written by the scroll
    /// view itself, which is what makes the header follow a swipe.
    @State private var visibleMonth: Date?
    /// Every month loaded this visit, by month key. Swiping back and forth
    /// over the same months was re-fetching each time and showing an empty
    /// grid until the rows landed — which is what read as flicker.
    @State private var monthCache: [String: [String: Checkin]] = [:]
    @State private var selected: Checkin?
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    /// The screen's margin, which each month carries itself rather than
    /// inheriting from the column. That is what lets the sheet run the full
    /// width and fade out over the margin instead of over the grid; it also
    /// puts two margins — a visible gap — between neighbouring months.
    private let pageMargin: CGFloat = 16

    private var calendar: Calendar { .current }
    private var cellHeight: CGFloat { DayCell.baseHeight * TypeScale.clamp(scale) }

    /// The month on screen. Nil until the scroll view reports one, which is
    /// the moment before it has settled anywhere — the last page.
    private var monthAnchor: Date { visibleMonth ?? months.last ?? .now }

    // Pushed from HomeView's toolbar, so it rides the home NavigationStack
    // rather than owning one.
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader.padding(.horizontal, pageMargin)
                // Seven columns cannot hold accessibility-size digits: at
                // the largest setting every two-digit day became "…". The
                // grid follows the text size up to the last regular step
                // and stops there; the cells still grow (TypeScale).
                Group {
                    weekdayHeader.padding(.horizontal, pageMargin)
                    // No margin here: the sheet spans the screen so a month
                    // can fade out over the margin rather than at the grid.
                    monthPager
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red).font(.footnote)
                        .padding(.horizontal, pageMargin)
                }
            }
            .padding(.vertical)
        }
        .background {
            // Neutral by design: a month holds many moods — the cells carry
            // the color, the backdrop stays the unworn ring.
            MoodBackground(theme: .neutral)
        }
        // Nothing to scroll when the month fits, which is the usual case —
        // without this the page rubber-bands vertically under a horizontal
        // swipe, and the two directions read as fighting each other.
        .scrollBounceBehavior(.basedOnSize)
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

    /// The months the sheet spans, oldest first so the current one is last
    /// and the view opens on it.
    private static func monthWindow(back: Int = 60) -> [Date] {
        let calendar = Calendar.current
        return (0...back).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: .now)
        }
    }

    private var monthStart: Date { monthStart(of: monthAnchor) }
    private var monthKey: String { monthKey(of: monthAnchor) }

    private func monthStart(of anchor: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
    }

    /// `yyyy-MM`, which is also the prefix of every `checkins.day` in that
    /// month — how one query's rows get sorted into three months.
    private func monthKey(of anchor: Date) -> String {
        String(LocalDay.string(for: monthStart(of: anchor)).prefix(7))
    }

    /// The month `months` away from the one on screen.
    private func shifted(_ months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: monthAnchor) ?? monthAnchor
    }

    /// A month's check-ins, or nothing while a month never seen this visit
    /// is still loading.
    private func checkins(of anchor: Date) -> [String: Checkin] {
        monthCache[monthKey(of: anchor)] ?? [:]
    }

    private func daysInMonth(of anchor: Date) -> Int {
        calendar.range(of: .day, in: .month, for: monthStart(of: anchor))?.count ?? 30
    }

    /// Empty cells before day 1, honoring the locale's first weekday.
    private func leadingBlanks(of anchor: Date) -> Int {
        let weekday = calendar.component(.weekday, from: monthStart(of: anchor))
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(monthAnchor, equalTo: .now, toGranularity: .month)
    }

    private func date(day: Int, of anchor: Date) -> Date {
        calendar.date(byAdding: .day, value: day - 1, to: monthStart(of: anchor)) ?? monthStart(of: anchor)
    }

    /// Always six rows, whatever the month needs. A month that fits in five
    /// would otherwise change the page height mid-swipe, and the grid would
    /// jump as one month replaced another.
    private var pagerHeight: CGFloat { 6 * cellHeight + 5 * gridSpacing }

    private var gridSpacing: CGFloat { 6 }

    // MARK: subviews

    /// Moves a month at a time for the chevrons. Swiping doesn't come
    /// through here — the scroll view does that itself.
    private func move(_ delta: Int) {
        guard let index = months.firstIndex(where: { monthKey(of: $0) == monthKey }) else { return }
        let target = index + delta
        guard months.indices.contains(target) else { return }
        withAnimation { visibleMonth = months[target] }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                move(-1)
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
                move(1)
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

    /// The months as one long sheet, paged by the scroll view itself rather
    /// than by a drag gesture of ours. That is what buys the native feel: a
    /// flick carries its velocity into the next month, a slow drag tracks
    /// the finger exactly, the ends rubber-band, and a swipe can interrupt
    /// the one still settling. Hand-rolling those is how it ends up stiff.
    private var monthPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(months, id: \.self) { anchor in
                    dayGrid(of: anchor)
                        .frame(height: pagerHeight)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $visibleMonth)
        .scrollIndicators(.hidden)
        // The current month is the last page, and the sheet opens on it.
        .defaultScrollAnchor(.trailing)
        .frame(height: pagerHeight)
        // A month leaves by thinning out rather than being sliced off at
        // the edge. The fade spans the margin exactly, so it never falls
        // across a day cell.
        .mask(edgeFade)
    }

    private var edgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: pageMargin)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: pageMargin)
        }
    }

    private func dayGrid(of anchor: Date) -> some View {
        let days = daysInMonth(of: anchor)
        let blanks = leadingBlanks(of: anchor)
        let month = checkins(of: anchor)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 7),
            spacing: gridSpacing
        ) {
            // Negative ids: LazyVGrid flattens identity across all its
            // ForEach children, so blank ids overlapping day numbers (1...)
            // silently drop those day cells.
            ForEach(-blanks..<0, id: \.self) { _ in
                Color.clear.frame(height: cellHeight)
            }
            ForEach(1...days, id: \.self) { day in
                let dayDate = date(day: day, of: anchor)
                let checkin = month[LocalDay.string(for: dayDate)]
                DayCell(day: day, checkin: checkin, isToday: calendar.isDateInToday(dayDate))
                    .onTapGesture {
                        if let checkin { selected = checkin }
                    }
            }
        }
        .padding(.horizontal, pageMargin)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func load() async {
        errorMessage = nil
        do {
            // All three months around this one in a single query: a
            // neighbour has to be filled in before the swipe starts, or the
            // month arriving is an empty grid. Re-run even when cached — the
            // current month changes under you when you check in.
            let ahead = shifted(1)
            let first = LocalDay.string(for: monthStart(of: shifted(-1)))
            let last = LocalDay.string(for: date(day: daysInMonth(of: ahead), of: ahead))
            let rows = try await withSkewRetry { try await CheckinRepository().mine(from: first, to: last) }
            // Seeded empty so a month with no check-ins is known to be
            // loaded rather than merely missing.
            var loaded = Dictionary(uniqueKeysWithValues: (-1...1).map { (monthKey(of: shifted($0)), [String: Checkin]()) })
            for row in rows { loaded[String(row.day.prefix(7)), default: [:]][row.day] = row }
            monthCache.merge(loaded) { _, fresh in fresh }
        } catch {
            // Leaving the tab cancels the .task mid-request; don't show
            // that as an error — reappearing restarts the load anyway.
            guard !error.isCancellation else { return }
            errorMessage = error.report("history.load")
        }
    }
}
