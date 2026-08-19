import SwiftUI

struct HistoryView: View {
    @State private var monthAnchor: Date = .now
    @State private var checkinsByDay: [String: Checkin] = [:]
    @State private var selected: Checkin?
    @State private var errorMessage: String?

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
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
            .navigationTitle("History")
            .task(id: monthKey) { await load() }
            .sheet(item: $selected) { checkin in
                CheckinDetailSheet(checkin: checkin)
                    .presentationDetents([.height(220)])
            }
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
            ForEach(0..<leadingBlanks, id: \.self) { _ in
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
            errorMessage = error.localizedDescription
        }
    }
}

private struct DayCell: View {
    let day: Int
    let checkin: Checkin?
    let isToday: Bool

    var body: some View {
        let mood = checkin.flatMap { Mood(rawValue: $0.mood) }
        RoundedRectangle(cornerRadius: 8)
            .fill(mood?.color.opacity(0.85) ?? Color(.tertiarySystemFill))
            .frame(height: 40)
            .overlay {
                Text("\(day)")
                    .font(.caption)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(mood != nil ? Color.white : .secondary)
            }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(.primary, lineWidth: 1.5)
                }
            }
    }
}

private struct CheckinDetailSheet: View {
    let checkin: Checkin

    var body: some View {
        VStack(spacing: 12) {
            let mood = Mood(rawValue: checkin.mood)
            HStack(spacing: 10) {
                Circle().fill(mood?.color ?? .gray).frame(width: 28, height: 28)
                Text(mood?.label ?? "—").font(.headline)
                if let emoji = checkin.emoji {
                    Text(emoji).font(.title2)
                }
            }
            Text(checkin.day).font(.subheadline).foregroundStyle(.secondary)
            if let note = checkin.note {
                Text(note)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
}
