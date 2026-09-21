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
    @State private var showInvite = false
    /// How many mutual contacts the server links to this account; nil until
    /// it loads, and on failure it stays nil rather than showing a wrong "0".
    @State private var mutualCount: Int?

    var body: some View {
        NavigationStack {
            Form {
                // Guarded as a whole: with no invite link configured and
                // the count not (yet) loaded, the section would be a header
                // with nothing under it.
                if Invite.url != nil || mutualCount != nil {
                    friends
                }

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
            .sheet(isPresented: $showInvite) { InviteSheet() }
            .onChange(of: showInvite) {
                // Same reason HomeView re-reports on closing this sheet:
                // nothing fires underneath a dismissal, so actions taken
                // afterwards would be filed under /invite.
                if !showInvite { Analytics.screen(.settings) }
            }
            .onAppear { Analytics.screen(.settings) }
            .task {
                userId = try? await Supa.client.auth.session.user.id.uuidString
                // Server-side, so it is right even with contacts access off.
                mutualCount = try? await ContactDirectory.mutualCount()
            }
        }
    }

    /// The invite lives at the top because it is the only thing in Settings
    /// that grows the board; the count under it is what makes an empty board
    /// legible ("nobody yet" rather than "something is broken").
    private var friends: some View {
        Section("Friends") {
            if Invite.url != nil {
                Button {
                    Analytics.track("invite_opened", ["source": "settings"])
                    showInvite = true
                } label: {
                    HStack {
                        Label("Invite a friend", systemImage: "person.badge.plus")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if let mutualCount {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Contacts")
                        Text(Invite.contactsSummary(count: mutualCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.2")
                }
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
