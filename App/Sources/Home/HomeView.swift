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

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if selected == nil {
                    picker
                } else {
                    board
                }
            }
            .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
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
            .task { await load() }
        }
    }

    private var picker: some View {
        VStack(spacing: 40) {
            Spacer()

            Text("How are you today?")
                .font(.title.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 24) {
                ForEach(choices, id: \.self) { choice in
                    EmojiButton(emoji: choice, isSelected: selected == choice, diameter: 100, fontSize: 64) {
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
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    if isChangingMood {
                        ForEach(choices, id: \.self) { choice in
                            EmojiButton(emoji: choice, isSelected: selected == choice, diameter: 48, fontSize: 30) {
                                lockIn(choice)
                                withAnimation { isChangingMood = false }
                            }
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

            BoardView()
        }
    }

    /// The six offered emoji: the fixed suggestions plus the user's daily
    /// wildcard, laid out by the grid as two rows of three.
    private var choices: [String] {
        MoodEmoji.suggestions + (wildcard.map { [$0] } ?? [])
    }

    private func load() async {
        do {
            let userId = try await Supa.client.auth.session.user.id
            wildcard = MoodEmoji.wildcard(for: userId, day: LocalDay.string())
            confirmed = try await CheckinRepository().today()?.emoji
            selected = confirmed
        } catch {
            // Backgrounding can cancel the .task mid-request; don't show
            // that as an error — reappearing restarts the load anyway.
            guard !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Tapping an emoji IS the check-in — no separate confirm step, and no
    /// waiting on the network: the selection moves immediately and the upsert
    /// rides along behind it. Saves are chained so rapid taps reach the server
    /// in the order they were made and the last tap is the one that sticks.
    private func lockIn(_ choice: String) {
        guard choice != selected else { return }
        withAnimation { selected = choice }
        errorMessage = nil

        let previous = saveTask
        saveTask = Task {
            await previous?.value
            do {
                try await CheckinRepository().saveToday(emoji: choice)
                confirmed = choice
            } catch {
                // A later tap that lands supersedes this failure; only roll
                // back if this is still what the user is looking at.
                if selected == choice {
                    withAnimation { selected = confirmed }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct EmojiButton: View {
    let emoji: String
    let isSelected: Bool
    let diameter: CGFloat
    let fontSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: fontSize))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(isSelected ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill)))
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: diameter > 60 ? 3 : 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(emoji) mood")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
