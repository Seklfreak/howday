import SwiftUI

struct HistoryView: View {
    @State private var monthAnchor: Date = .now
    /// Every month loaded this visit, by month key. Swiping back and forth
    /// over the same months was re-fetching each time and showing an empty
    /// grid until the rows landed — which is what read as flicker.
    @State private var monthCache: [String: [String: Checkin]] = [:]
    @State private var selected: Checkin?
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
    /// The width of one month, measured from the layout. `step` needs the
    /// real number to slide a whole page.
    @State private var pageWidth: CGFloat = 0
    /// How far the month has been dragged, live. Deliberately not
    /// `@GestureState`, which snaps back to zero the instant the finger
    /// lifts: the grid would jump to centre and only then slide away. This
    /// animates to zero as part of the same change that moves the month,
    /// so the drag and the slide are one movement.
    @State private var dragX: CGFloat = 0

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
                    monthPager
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
        // Nothing to scroll when the month fits, which is the usual case —
        // without this the view still rubber-bands vertically under a
        // horizontal swipe, and the two gestures read as fighting.
        .scrollBounceBehavior(.basedOnSize)
        // Swipe to flip through months, the way a calendar does. Simultaneous
        // rather than exclusive so the scroll view keeps vertical drags at
        // accessibility text sizes, where the grid really is taller than the
        // screen; the dominance test below is what keeps a diagonal drag
        // from doing both at once. The chevrons stay — a gesture is not
        // discoverable, and VoiceOver has no way to perform this one.
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onChanged { drag in
                    guard isHorizontal(drag.translation) else { return }
                    // A pull toward the future drags heavily and springs
                    // back: there is nothing ahead of today to show, and
                    // resistance says so better than simply not moving.
                    let travel = drag.translation.width
                    dragX = travel < 0 && isCurrentMonth ? travel / 4 : travel
                }
                .onEnded { drag in
                    guard isHorizontal(drag.translation), abs(drag.translation.width) > 60 else {
                        withAnimation(.spring(duration: 0.3)) { dragX = 0 }
                        return
                    }
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

    /// Whether a drag is for the months rather than for the scroll view.
    /// Clearly horizontal, not merely more horizontal: a lazy diagonal
    /// scroll should move the page and leave the month alone.
    private func isHorizontal(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * 1.5
    }

    /// Moves by whole months, and is the only way the month changes — the
    /// chevrons and the swipe share it so both animate the same way and
    /// both stop at the current month. There is nothing to show ahead of
    /// today, and a forward swipe into an empty grid reads as a bug.
    private func step(months: Int) {
        guard months < 0 || !isCurrentMonth,
              pageWidth > 0,
              let moved = calendar.date(byAdding: .month, value: months, to: monthAnchor) else {
            withAnimation(.spring(duration: 0.3)) { dragX = 0 }
            return
        }
        // Slide the sheet a whole page, so the month already half on screen
        // simply finishes arriving. Only once it has landed does the anchor
        // move and the offset reset — both without animation, which puts the
        // new month exactly where the old one was standing.
        withAnimation(.easeInOut(duration: 0.28)) {
            dragX = CGFloat(-months) * pageWidth
        } completion: {
            var settle = Transaction()
            settle.disablesAnimations = true
            withTransaction(settle) {
                monthAnchor = moved
                dragX = 0
            }
        }
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

    /// Three months side by side — last, this, next — in a window one month
    /// wide. Dragging moves the whole sheet, so the month you are pulling
    /// toward is already on screen and already filled in, rather than
    /// appearing once the swipe is over.
    private var monthPager: some View {
        GeometryReader { proxy in
            let page = proxy.size.width
            HStack(spacing: 0) {
                dayGrid(of: shifted(-1)).frame(width: page)
                dayGrid(of: monthAnchor).frame(width: page)
                // Nothing to show ahead of today: the page stays blank so
                // the resisted pull reveals an edge, not an empty calendar.
                Group {
                    if isCurrentMonth {
                        Color.clear
                    } else {
                        dayGrid(of: shifted(1))
                    }
                }
                .frame(width: page)
            }
            .offset(x: -page + dragX)
            .onChange(of: page, initial: true) { _, width in pageWidth = width }
        }
        .frame(height: pagerHeight)
        // The neighbours are always beside the window; this is what keeps
        // them out of sight until they are dragged in.
        .clipped()
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
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func load() async {
        errorMessage = nil
        do {
            // All three visible months in one query: a neighbour has to be
            // filled in before the drag starts, or the month sliding in is
            // an empty grid. Re-run even when cached — the current month
            // changes under you when you check in.
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
