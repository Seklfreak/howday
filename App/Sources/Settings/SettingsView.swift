import Supabase
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var userId: String?
    @State private var didCopyUserId = false

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
                        Task {
                            // Drop the push token first — signed-out devices
                            // must stop receiving friend check-ins.
                            await PushRegistrar.unregister()
                            try? await Supa.client.auth.signOut()
                        }
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

                if let userId {
                    Section {
                        Button { copy(userId) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("User ID")
                                    Text(userId)
                                        .font(.system(.caption2, design: .monospaced))
                                }
                                Spacer()
                                Image(systemName: didCopyUserId ? "checkmark" : "doc.on.doc")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } footer: {
                        Text("Include this if you report a problem.")
                    }
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
            .onAppear { Analytics.screen(.settings) }
            .task {
                userId = try? await Supa.client.auth.session.user.id.uuidString
            }
        }
    }

    /// Copies the ID and flips the trailing icon to a checkmark briefly, so the
    /// tap has visible feedback without a toast.
    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        didCopyUserId = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopyUserId = false
        }
    }

    private func deleteAccount() {
        isDeleting = true
        Task {
            do {
                // Clears the locally remembered push token; the server rows
                // cascade away with the account.
                await PushRegistrar.unregister()
                struct Result: Decodable { let deleted: Bool }
                let _: Result = try await Supa.client.functions.invoke("delete-account")
                Analytics.track("account_deleted")
                // Server-side account is gone; drop the local session. The
                // auth state change flips the app back to sign-in.
                try? await Supa.client.auth.signOut(scope: .local)
            } catch {
                errorMessage = error.report("settings.deleteAccount")
            }
            isDeleting = false
        }
    }
}
