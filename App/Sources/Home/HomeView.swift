import Supabase
import SwiftUI

/// The app's single screen. Until you've checked in, the mood picker fills
/// it; picking an emoji IS the check-in, and the friends board takes over
/// with the picker collapsed into a compact bar for changing your mind.
/// History and Settings live in the toolbar — there are no tabs.
struct HomeView: View {
    /// What the picker shows right now — updated the instant a tap lands.
    @State private var selected: String?
    /// The last emoji the server acknowledged, so a failed save can roll back.
    @State private var confirmed: String?
    @State private var wildcard: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showSettings = false
    /// Whether the collapsed mood bar is spread open to offer all choices.
    @State private var isChangingMood = false
    @State private var saveTask: Task<Void, Never>?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ZStack {
                MoodBackground(theme: currentTheme)
                Group {
                    if isLoading {
                        ProgressView()
                    } else if selected == nil {
                        picker
                    } else {
                        board
                    }
                }
            }
            .navigationTitle(title)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                NavigationLink {
                    HistoryView()
                } label: {
                    Image(systemName: "calendar")
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onChange(of: showSettings) {
                // Dismissing a sheet doesn't fire onAppear on the view beneath
                // it, so without this the board stays "on" /settings and every
                // action taken after closing it is filed under Settings.
                if !showSettings { Analytics.screen(selected == nil ? .home : .board) }
            }
            .task { await load() }
            .onAppear {
                // The first pageview comes from load(); this one catches
                // coming back from History, which leaves this view mounted.
                if !isLoading { Analytics.screen(selected == nil ? .home : .board) }
            }
        }
        .tint(currentTheme.accent)
    }

    /// The theme everything on this screen derives from: your mood's colors
    /// once you've picked, the unworn ring's pearl-neutral before.
    private var currentTheme: MoodTheme {
        MoodTheme.forEmoji(selected)
    }

    private var picker: some View {
        VStack(spacing: 40) {
            Spacer()

            Text("How are you today?")
                .font(.title.weight(.semibold))

            // Two columns at the accessibility sizes: the circles grow with
            // the text (see TypeScale), and three of them no longer fit.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: pickerColumns), spacing: 24) {
                ForEach(choices, id: \.self) { choice in
                    EmojiButton(
                        emoji: choice, isSelected: selected == choice, isWildcard: choice == wildcard,
                        diameter: 100, fontSize: 64
                    ) {
                        lockIn(choice)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .sensoryFeedback(.success, trigger: selected)

            Text(errorMessage ?? " ")
                .foregroundStyle(.red)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()
        }
    }

    /// Checked in: just your mood, with the friends board underneath.
    /// Tapping the emoji spreads the bar back into the six choices; picking
    /// one (or retapping your current mood) collapses it again.
    private var board: some View {
        // Handed to BoardView as its scroll-view header rather than stacked
        // above it: outside the scroll view the mood bar stayed pinned while
        // a pull dragged the board out from under it.
        BoardView {
            VStack(spacing: 6) {
                Group {
                    if isChangingMood {
                        // A row while six circles fit; at large text sizes
                        // they don't, and the bar wraps into two rows of
                        // three rather than running off the screen.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { moodBarChoices }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                moodBarChoices
                            }
                            .padding(.horizontal, 24)
                        }
                    } else if let selected {
                        EmojiButton(emoji: selected, isSelected: true, diameter: 48, fontSize: 30) {
                            withAnimation { isChangingMood = true }
                        }
                    }
                }
                .sensoryFeedback(.success, trigger: selected)
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 8)

            Divider()
        }
    }

    /// The spread-open mood bar's six buttons, shared by both of its layouts.
    private var moodBarChoices: some View {
        ForEach(choices, id: \.self) { choice in
            EmojiButton(
                emoji: choice, isSelected: selected == choice, isWildcard: choice == wildcard,
                diameter: 48, fontSize: 30
            ) {
                lockIn(choice)
                withAnimation { isChangingMood = false }
            }
        }
    }

    /// The six offered emoji: the fixed suggestions plus the user's daily
    /// wildcard, laid out by the grid as two rows of three.
    private var choices: [String] {
        MoodEmoji.suggestions + (wildcard.map { [$0] } ?? [])
    }

    private var pickerColumns: Int {
        dynamicTypeSize.isAccessibilitySize ? 2 : 3
    }

    /// "Saturday, Sep 19" — or "Sat, Sep 19" at the accessibility sizes,
    /// where the large title otherwise truncates to "Saturday, S…".
    private var title: String {
        Date.now.formatted(.dateTime.weekday(dynamicTypeSize.isAccessibilitySize ? .abbreviated : .wide).month().day())
    }

    private func load() async {
        do {
            let userId = try await Supa.client.auth.session.user.id
            wildcard = MoodEmoji.wildcard(for: userId, day: LocalDay.string())
            confirmed = try await withSkewRetry { try await CheckinRepository().today() }?.emoji
            selected = confirmed
        } catch {
            // Backgrounding can cancel the .task mid-request; don't show
            // that as an error — reappearing restarts the load anyway.
            guard !error.isCancellation else { return }
            errorMessage = error.report("home.load")
        }
        isLoading = false
        // The picker and the board are the same view in its two states, so
        // which one the load lands on is the pageview worth recording.
        Analytics.screen(selected == nil ? .home : .board)
    }

    /// Tapping an emoji IS the check-in — no separate confirm step, and no
    /// waiting on the network: the selection moves immediately and the upsert
    /// rides along behind it. Saves are chained so rapid taps reach the server
    /// in the order they were made and the last tap is the one that sticks.
    private func lockIn(_ choice: String) {
        guard choice != selected else { return }
        // Read from `selected`, not `confirmed`: it moves with the tap, so
        // rapid taps before the first save lands can't both count as first.
        let isFirstToday = selected == nil
        withAnimation { selected = choice }
        errorMessage = nil
        // The board takes over the moment the first mood lands, not when the
        // save comes back — record the screen the user is actually looking at.
        if isFirstToday { Analytics.screen(.board) }

        let previous = saveTask
        saveTask = Task {
            await previous?.value
            do {
                try await withSkewRetry { try await CheckinRepository().saveToday(emoji: choice) }
                confirmed = choice
                // The day's done; a reminder landing later would be noise.
                ReminderScheduler.cancelToday()
                // The emoji stays out of it — the mood is the private part.
                Analytics.track(isFirstToday ? "checkin_saved" : "checkin_edited")
            } catch {
                // A later tap that lands supersedes this failure; only roll
                // back if this is still what the user is looking at.
                if selected == choice {
                    withAnimation { selected = confirmed }
                    errorMessage = error.report("home.save")
                }
            }
        }
    }
}

private struct EmojiButton: View {
    let emoji: String
    let isSelected: Bool
    var isWildcard = false
    /// Base sizes at the default text size; both follow Dynamic Type.
    let diameter: CGFloat
    let fontSize: CGFloat
    let action: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    /// Each button rings and glows in its own mood's color, not a shared
    /// accent — the ring wears the color it would turn.
    private var theme: MoodTheme { MoodTheme.forEmoji(emoji) }

    private var scaledDiameter: CGFloat { diameter * TypeScale.clamp(scale) }

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: fontSize * TypeScale.clamp(scale)))
                .frame(width: scaledDiameter, height: scaledDiameter)
                .background(Circle().fill(.white.opacity(isSelected ? 0.10 : 0.06)))
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(theme.accent, lineWidth: diameter > 60 ? 3 : 2.5)
                    } else {
                        // The daily wildcard keeps a dashed "surprise" ring.
                        Circle().strokeBorder(
                            .white.opacity(0.12),
                            style: StrokeStyle(lineWidth: 1.5, dash: isWildcard ? [6, 5] : [])
                        )
                    }
                }
                .shadow(color: isSelected ? theme.accent.opacity(0.55) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(emoji) mood")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
