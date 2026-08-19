import Supabase
import SwiftUI

struct CheckInView: View {
    @State private var existing: Checkin?
    @State private var wildcard: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSettings = false

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
                    EmojiButton(emoji: choice, isSelected: existing?.emoji == choice) {
                        lockIn(choice)
                    }
                }
            }
            .padding(.horizontal, 24)
            .disabled(isSaving)
            .sensoryFeedback(.success, trigger: existing?.emoji)

            Group {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if existing != nil {
                    Text("Checked in — tap another emoji to change it until midnight.")
                        .foregroundStyle(.secondary)
                }
            }
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
            existing = try await CheckinRepository().today()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Tapping an emoji IS the check-in — no separate confirm step.
    private func lockIn(_ choice: String) {
        guard choice != existing?.emoji else { return }
        errorMessage = nil
        isSaving = true
        Task {
            do {
                try await CheckinRepository().saveToday(emoji: choice)
                existing = try await CheckinRepository().today()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
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
