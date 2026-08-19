import Supabase
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profile: Profile?
    @State private var name = ""
    @State private var nameSaved = false
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Display name") {
                    HStack {
                        TextField("Your name", text: $name)
                            .onChange(of: name) { nameSaved = false }
                        if nameSaved {
                            Image(systemName: "checkmark").foregroundStyle(.green)
                        } else {
                            Button("Save") { saveName() }
                                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                    || name == profile?.displayName)
                        }
                    }
                }

                Section {
                    NavigationLink("Daily reminder") {
                        ReminderSettingsView()
                    }
                }

                if let profile {
                    Section("Invite code") {
                        HStack {
                            Text(profile.inviteCode).font(.system(.body, design: .monospaced))
                            Spacer()
                            ShareLink(item: "Join me on Moodring! My invite code: \(profile.inviteCode)") {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }

                Section {
                    Button("Sign out") {
                        Task { try? await Supa.client.auth.signOut() }
                    }
                    Button("Delete account", role: .destructive) {
                        confirmDelete = true
                    }
                    .disabled(isDeleting)
                } footer: {
                    Text("Deleting your account permanently removes your profile, check-ins, and friendships.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) { deleteAccount() }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    private func load() async {
        do {
            profile = try await ProfileRepository().myProfile()
            name = profile?.displayName ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveName() {
        Task {
            do {
                try await ProfileRepository().updateDisplayName(name.trimmingCharacters(in: .whitespaces))
                nameSaved = true
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteAccount() {
        isDeleting = true
        Task {
            do {
                struct Result: Decodable { let deleted: Bool }
                let _: Result = try await Supa.client.functions.invoke("delete-account")
                // Server-side account is gone; drop the local session. The
                // auth state change flips the app back to sign-in.
                try? await Supa.client.auth.signOut(scope: .local)
            } catch {
                errorMessage = error.localizedDescription
            }
            isDeleting = false
        }
    }
}
