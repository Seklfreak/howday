import Supabase
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Daily reminder") {
                        ReminderSettingsView()
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
                    Text("Deleting your account permanently removes your check-ins and contact matches.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
