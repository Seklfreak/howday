import Supabase
import SwiftUI

struct BoardView: View {
    /// Bound to the tab selection so the gate can jump to the check-in tab.
    @Binding var tabSelection: MainTab

    @State private var board = BoardState()
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if board.mine == nil {
                    gate
                } else {
                    grid
                }
            }
            .navigationTitle("Friends today")
            .task {
                await load()
                await listenForChanges()
            }
            .refreshable { await load() }
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
                    description: Text("Add friends to see how they're doing.")
                )
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.footnote)
            }
        }
    }

    private func load() async {
        do {
            board = try await BoardRepository().load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
        for await _ in changes {
            await load()
        }
    }
}

private struct BoardCard: View {
    let entry: BoardEntry

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 56, height: 56)
                if let emoji = entry.checkin?.emoji {
                    Text(emoji).font(.system(size: 30))
                } else {
                    Image(systemName: "zzz").foregroundStyle(.secondary)
                }
            }
            Text(entry.profile.displayName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if entry.checkin == nil {
                Text("Not yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = entry.checkin?.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
