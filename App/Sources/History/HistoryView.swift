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
    /// How far the finger has moved. `@GestureState` so a drag that never
    /// ends — cancelled by the system, interrupted by a call — puts the
    /// sheet back on its own. Left to `@State` it stuck part-way and the
    /// neighbouring month sat visible at the edge for good.
    @GestureState private var dragX: CGFloat = 0
    /// Where the sheet rests between gestures: picked up from the drag the
    /// moment the finger lifts, so the hand-over is invisible, then
    /// animated home. This is what lets the release keep moving instead of
    /// snapping to centre first.
    @State private var settleX: CGFloat = 0

    /// What the sheet is actually offset by.
    private var sheetX: CGFloat { dragX + settleX }

    /// A month's width plus the gap to the next one.
    private var pageAdvance: CGFloat { pageWidth + pageGutter }

    /// Space between months. Without it they touch, and the one arriving
    /// reads as more rows of the one leaving.
    private let pageGutter: CGFloat = 28

    /// The screen's margin, which each month carries itself rather than
    /// inheriting from the column. That is what lets the sheet run the
    /// full width and fade out over the margin instead of over the grid.
    private let pageMargin: CGFloat = 16

    private var calendar: Calendar { .current }
    private var cellHeight: CGFloat { DayCell.baseHeight * TypeScale.clamp(scale) }

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
                .updating($dragX) { drag, live, _ in
                    guard isHorizontal(drag.translation) else { return }
                    live = resisted(drag.translation.width)
                }
                .onEnded { drag in
                    // Take the offset over from the gesture in the same
                    // moment it lets go, so nothing moves on hand-over.
                    settleX = isHorizontal(drag.translation) ? resisted(drag.translation.width) : 0
                    guard isHorizontal(drag.translation), abs(drag.translation.width) > 60 else {
                        withAnimation(.spring(duration: 0.3)) { settleX = 0 }
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

    /// A pull toward the future drags heavily and springs back: there is
    /// nothing ahead of today to show, and resistance says so better than
    /// simply refusing to move.
    private func resisted(_ travel: CGFloat) -> CGFloat {
        travel < 0 && isCurrentMonth ? travel / 4 : travel
    }

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
            withAnimation(.spring(duration: 0.3)) { settleX = 0 }
            return
        }
        // Slide the sheet a whole page, so the month already half on screen
        // simply finishes arriving. Only once it has landed does the anchor
        // move and the offset reset — both without animation, which puts the
        // new month exactly where the old one was standing.
        withAnimation(.easeInOut(duration: 0.28)) {
            settleX = CGFloat(-months) * pageAdvance
        } completion: {
            var landing = Transaction()
            landing.disablesAnimations = true
            withTransaction(landing) {
                monthAnchor = moved
                settleX = 0
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
            HStack(spacing: pageGutter) {
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
            .offset(x: -(page + pageGutter) + sheetX)
            .onChange(of: page, initial: true) { _, width in pageWidth = width }
        }
        .frame(height: pagerHeight)
        // A month leaves by thinning out rather than being sliced off at
        // the edge; it is also what hides the neighbours at rest. The fade
        // spans the margin exactly, so it never touches a day cell.
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
