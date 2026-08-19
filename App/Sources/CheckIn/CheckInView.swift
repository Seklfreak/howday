import Supabase
import SwiftUI

struct CheckInView: View {
    /// What the grid shows right now — updated the instant a tap lands.
    @State private var selected: String?
    /// The last emoji the server acknowledged, so a failed save can roll back.
    @State private var confirmed: String?
    @State private var wildcard: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    picker
                }
            }
            .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
            .toolbar {
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
                    EmojiButton(emoji: choice, isSelected: selected == choice) {
                        lockIn(choice)
                    }
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
            // Leaving the tab cancels the .task mid-request; don't show
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
        selected = choice
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
                    selected = confirmed
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct EmojiButton: View {
    let emoji: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 64))
                .frame(width: 100, height: 100)
                .background(Circle().fill(isSelected ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill)))
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(emoji) mood")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
