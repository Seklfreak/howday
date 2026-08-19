import SwiftUI

struct CheckInView: View {
    @State private var existing: Checkin?
    @State private var selectedMood: Mood?
    @State private var emoji = ""
    @State private var note = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var justSaved = false
    @State private var errorMessage: String?
    @State private var showReminderSettings = false
    @AppStorage("reminderConfigured") private var reminderConfigured = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    form
                }
            }
            .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
            .toolbar {
                Button {
                    showReminderSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            .sheet(isPresented: $showReminderSettings) {
                ReminderSettingsView()
            }
            .task { await load() }
        }
    }

    private var form: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    ForEach(Mood.allCases) { mood in
                        MoodButton(mood: mood, isSelected: selectedMood == mood) {
                            selectedMood = mood
                            justSaved = false
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text(existing == nil ? "How are you today?" : "Today's check-in")
            }

            Section {
                TextField("Emoji (optional)", text: $emoji)
                    .onChange(of: emoji) { _, new in
                        if new.count > 2 { emoji = String(new.prefix(2)) }
                        justSaved = false
                    }
                TextField("Add a note (optional)", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: note) { _, new in
                        if new.count > 140 { note = String(new.prefix(140)) }
                        justSaved = false
                    }
            }

            Section {
                Button(action: save) {
                    if isSaving {
                        ProgressView()
                    } else if justSaved {
                        Label("Checked in", systemImage: "checkmark")
                    } else {
                        Text(existing == nil ? "Check in" : "Update check-in")
                    }
                }
                .disabled(isSaving || selectedMood == nil || justSaved)
            } footer: {
                if existing != nil {
                    Text("You can edit today's check-in until midnight.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            if !reminderConfigured {
                Section {
                    NavigationLink {
                        ReminderSettingsView()
                    } label: {
                        Label("Set a daily reminder", systemImage: "bell")
                    }
                } footer: {
                    Text("A quiet daily nudge, at a time you pick. Checking in is what lets you see your friends' moods.")
                }
            }
        }
    }

    private func load() async {
        do {
            existing = try await CheckinRepository().today()
            if let existing {
                selectedMood = Mood(rawValue: existing.mood)
                emoji = existing.emoji ?? ""
                note = existing.note ?? ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save() {
        guard let mood = selectedMood else { return }
        errorMessage = nil
        isSaving = true
        Task {
            do {
                try await CheckinRepository().saveToday(mood: mood, emoji: emoji, note: note)
                existing = try await CheckinRepository().today()
                justSaved = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

private struct MoodButton: View {
    let mood: Mood
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(mood.color)
                    .frame(width: 44, height: 44)
                    .overlay {
                        if isSelected {
                            Circle().strokeBorder(.primary, lineWidth: 3)
                        }
                    }
                Text(mood.label)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mood.label) mood")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
