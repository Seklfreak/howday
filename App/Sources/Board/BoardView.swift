import Supabase
import SwiftUI
import UIKit

struct BoardView: View {
    /// Bound to the tab selection so the gate can jump to the check-in tab.
    @Binding var tabSelection: MainTab

    @Environment(\.scenePhase) private var scenePhase
    @State private var board = BoardState()
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var contactsDenied = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if contactsDenied {
                    contactsPrompt
                } else if board.mine == nil {
                    gate
                } else {
                    grid
                }
            }
            .navigationTitle("Friends today")
            .task { await listenForChanges() }
            .refreshable { await load() }
            .onChange(of: scenePhase) {
                // Coming back to the foreground: the socket may have dropped
                // and missed events are never replayed — refetch. This is
                // also what makes a notification tap land on fresh data.
                if scenePhase == .active {
                    Task { await load() }
                }
            }
        }
    }

    private var gate: some View {
        ContentUnavailableView {
            Label("Check in first", systemImage: "lock")
        } description: {
            Text("Your friends' moods unlock once you've shared yours for today.")
        } actions: {
            Button("Check in") { tabSelection = .today }
                .buttonStyle(.borderedProminent)
        }
    }

    private var contactsPrompt: some View {
        ContentUnavailableView {
            Label("Contacts access is off", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("Moodring is contacts-based — friends appear automatically when you're in each other's contacts.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(board.entries) { entry in
                    BoardCard(entry: entry)
                }
            }
            .padding()
            if board.entries.isEmpty {
                ContentUnavailableView(
                    "No friends yet",
                    systemImage: "person.2",
                    description: Text("Friends appear automatically once you and they have each other in your contacts.")
                )
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.footnote)
            }
        }
    }

    private func load() async {
        // First board visit triggers the contacts prompt; afterwards this is
        // a no-op and isAuthorized reflects the user's answer.
        await ContactDirectory.requestAccess()
        contactsDenied = !ContactDirectory.isAuthorized
        if !contactsDenied {
            // No-op unless the app was foregrounded or contacts changed
            // since the last upload.
            await ContactDirectory.syncIfNeeded()
            do {
                board = try await BoardRepository().load()
                errorMessage = nil
            } catch {
                // Leaving the tab cancels the .task mid-request; don't show
                // that as an error — reappearing restarts the load anyway.
                guard !error.isCancellation else { return }
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    /// Reload on any checkins change (insert or update). RLS already limits
    /// events to rows this user can see; reloading keeps the logic dumb and
    /// correct. Runs until the surrounding .task is cancelled.
    private func listenForChanges() async {
        // Push the user's JWT to the realtime socket BEFORE subscribing.
        // Without it the socket is anonymous, RLS filters out every row,
        // and events silently never arrive (verified against this project).
        if let token = try? await Supa.client.auth.session.accessToken {
            await Supa.client.realtimeV2.setAuth(token)
        }
        let channel = Supa.client.channel("board-checkins")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "checkins")
        await channel.subscribe()
        defer { Task { await Supa.client.removeChannel(channel) } }
        // Initial load AFTER subscribing: there is no realtime catch-up, so
        // a check-in landing mid-load would otherwise stay invisible until
        // the next manual refresh.
        await load()
        for await _ in changes {
            await load()
        }
    }
}

private struct BoardCard: View {
    let entry: BoardEntry

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                avatar
                if let emoji = entry.checkin?.emoji {
                    Text(emoji)
                        .font(.system(size: 24))
                        .padding(2)
                        .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                        .offset(x: 8, y: 8)
                }
            }
            Text(entry.identity.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if entry.checkin == nil {
                Text("Not yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    /// The contact's photo from the viewer's address book, or a monogram.
    @ViewBuilder
    private var avatar: some View {
        if let data = entry.identity.photo, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 56, height: 56)
                Text(entry.identity.name.prefix(1).uppercased())
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
