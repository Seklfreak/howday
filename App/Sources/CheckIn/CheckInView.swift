import SwiftUI

struct CheckInView: View {
    @State private var existing: Checkin?
    @State private var emoji = ""
    @State private var customEmoji = ""
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
                SettingsView()
            }
            .task { await load() }
        }
    }

    private var form: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    ForEach(MoodEmoji.suggestions, id: \.self) { suggestion in
                        EmojiButton(emoji: suggestion, isSelected: emoji == suggestion) {
                            emoji = suggestion
                            customEmoji = ""
                            justSaved = false
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                TextField("Or any other emoji", text: $customEmoji)
                    .onChange(of: customEmoji) { _, new in
                        justSaved = false
                        if let picked = new.firstEmoji {
                            emoji = picked
                            if new != picked { customEmoji = picked }
                        } else {
                            // Non-emoji input is dropped; losing the custom
                            // emoji clears the selection too.
                            if !new.isEmpty { customEmoji = "" }
                            if !MoodEmoji.suggestions.contains(emoji) { emoji = "" }
                        }
                    }
            } header: {
                Text(existing == nil ? "How are you today?" : "Today's check-in")
            }

            Section {
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
                .disabled(isSaving || emoji.isEmpty || justSaved)
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
                emoji = existing.emoji
                if !MoodEmoji.suggestions.contains(existing.emoji) {
                    customEmoji = existing.emoji
                }
                note = existing.note ?? ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save() {
        guard !emoji.isEmpty else { return }
        errorMessage = nil
        isSaving = true
        Task {
            do {
                try await CheckinRepository().saveToday(emoji: emoji, note: note)
                existing = try await CheckinRepository().today()
                justSaved = true
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
                .font(.system(size: 28))
                .frame(width: 48, height: 48)
                .background(Circle().fill(isSelected ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill)))
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(emoji) mood")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
