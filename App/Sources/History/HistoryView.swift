import SwiftUI

struct HistoryView: View {
    @State private var monthAnchor: Date = .now
    @State private var checkinsByDay: [String: Checkin] = [:]
    @State private var selected: Checkin?
    @State private var errorMessage: String?

    private var calendar: Calendar { .current }

    // Pushed from HomeView's toolbar, so it rides the home NavigationStack
    // rather than owning one.
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader
                weekdayHeader
                dayGrid
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
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("History")
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

    private var monthHeader: some View {
        HStack {
            Button {
                monthAnchor = calendar.date(byAdding: .month, value: -1, to: monthAnchor) ?? monthAnchor
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(monthStart.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button {
                monthAnchor = calendar.date(byAdding: .month, value: 1, to: monthAnchor) ?? monthAnchor
            } label: {
                Image(systemName: "chevron.right")
            }
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
                Color.clear.frame(height: 40)
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
            let rows = try await CheckinRepository().mine(from: first, to: last)
            checkinsByDay = Dictionary(uniqueKeysWithValues: rows.map { ($0.day, $0) })
        } catch {
            // Leaving the tab cancels the .task mid-request; don't show
            // that as an error — reappearing restarts the load anyway.
            guard !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct DayCell: View {
    let day: Int
    let checkin: Checkin?
    let isToday: Bool

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

    private var theme: MoodTheme { MoodTheme.forEmoji(checkin.emoji) }

    /// "Wednesday, August 19" instead of the stored "2026-08-19".
    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: checkin.day) else { return checkin.day }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(checkin.emoji)
                .font(.system(size: 44))
                .frame(width: 84, height: 84)
                .background(Circle().fill(.white.opacity(0.07)))
                .overlay(Circle().strokeBorder(theme.accent, lineWidth: 3))
                .shadow(color: theme.accent.opacity(0.55), radius: 12)
            Text(dateText).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
        .presentationBackground(theme.deep)
    }
}
