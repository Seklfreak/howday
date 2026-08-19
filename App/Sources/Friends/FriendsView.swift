import SwiftUI

struct FriendsView: View {
    @State private var state = FriendsState()
    @State private var myCode: String?
    @State private var codeInput = ""
    @State private var matches: [ContactMatch]?
    @State private var requestedProfileIds: Set<UUID> = []
    @State private var isMatching = false
    @State private var isRedeeming = false
    @State private var infoMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                contactsSection
                inviteSection
                if !state.incoming.isEmpty { incomingSection }
                if !state.outgoing.isEmpty { outgoingSection }
                friendsSection
                if let infoMessage {
                    Section { Text(infoMessage).foregroundStyle(.secondary) }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Friends")
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }

    // MARK: sections

    private var contactsSection: some View {
        Section {
            if let matches {
                if matches.isEmpty {
                    Text("None of your contacts are on Moodring yet — invite them with your code below.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matches) { match in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(match.contactName)
                                if match.displayName != match.contactName {
                                    Text("“\(match.displayName)” on Moodring")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            matchButton(for: match)
                        }
                    }
                }
            }
            Button {
                runMatching()
            } label: {
                if isMatching {
                    ProgressView()
                } else {
                    Label(matches == nil ? "Find friends in contacts" : "Search again",
                          systemImage: "person.crop.circle.badge.magnifyingglass")
                }
            }
            .disabled(isMatching)
        } header: {
            Text("From your contacts")
        } footer: {
            Text("Numbers are hashed on this device before matching and never stored on the server.")
        }
    }

    @ViewBuilder
    private func matchButton(for match: ContactMatch) -> some View {
        if state.friends.contains(where: { $0.profile.id == match.profileId }) {
            Text("Friends").foregroundStyle(.secondary)
        } else if requestedProfileIds.contains(match.profileId)
            || state.relatedProfileIds.contains(match.profileId) {
            Text("Requested").foregroundStyle(.secondary)
        } else {
            Button("Add") {
                Task {
                    await run {
                        try await FriendsRepository().sendRequest(to: match.profileId)
                        requestedProfileIds.insert(match.profileId)
                        await refresh()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var inviteSection: some View {
        Section {
            if let myCode {
                HStack {
                    Text(myCode).font(.system(.body, design: .monospaced))
                    Spacer()
                    ShareLink(item: "Join me on Moodring! My invite code: \(myCode)") {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            HStack {
                TextField("Enter a friend's code", text: $codeInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Redeem") { redeem() }
                    .disabled(isRedeeming || codeInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Invite code")
        } footer: {
            Text("Share your code with friends who aren't in your contacts.")
        }
    }

    private var incomingSection: some View {
        Section("Requests") {
            ForEach(state.incoming, id: \.friendshipId) { entry in
                HStack {
                    Text(entry.profile.displayName)
                    Spacer()
                    Button("Accept") {
                        Task {
                            await run {
                                try await FriendsRepository().accept(friendshipId: entry.friendshipId)
                                await refresh()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Decline") {
                        Task {
                            await run {
                                try await FriendsRepository().remove(friendshipId: entry.friendshipId)
                                await refresh()
                            }
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var outgoingSection: some View {
        Section("Sent") {
            ForEach(state.outgoing, id: \.friendshipId) { entry in
                HStack {
                    Text(entry.profile.displayName)
                    Spacer()
                    Text("Pending").foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Cancel", role: .destructive) {
                        Task {
                            await run {
                                try await FriendsRepository().remove(friendshipId: entry.friendshipId)
                                await refresh()
                            }
                        }
                    }
                }
            }
        }
    }

    private var friendsSection: some View {
        Section("Friends") {
            if state.friends.isEmpty {
                Text("No friends yet.").foregroundStyle(.secondary)
            }
            ForEach(state.friends, id: \.friendshipId) { entry in
                Text(entry.profile.displayName)
                    .swipeActions {
                        Button("Unfriend", role: .destructive) {
                            Task {
                                await run {
                                    try await FriendsRepository().remove(friendshipId: entry.friendshipId)
                                    await refresh()
                                }
                            }
                        }
                    }
            }
        }
    }

    // MARK: actions

    private func refresh() async {
        do {
            state = try await FriendsRepository().state()
            if myCode == nil {
                myCode = try await ProfileRepository().myProfile().inviteCode
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runMatching() {
        infoMessage = nil
        errorMessage = nil
        isMatching = true
        Task {
            do {
                matches = try await ContactMatcher.findMatches()
            } catch {
                errorMessage = error.localizedDescription
            }
            isMatching = false
        }
    }

    private func redeem() {
        isRedeeming = true
        Task {
            await run {
                let name = try await FriendsRepository()
                    .redeemInvite(code: codeInput.trimmingCharacters(in: .whitespaces))
                infoMessage = name.map { "Request sent to \($0)." }
                codeInput = ""
                await refresh()
            }
            isRedeeming = false
        }
    }

    private func run(_ work: () async throws -> Void) async {
        infoMessage = nil
        errorMessage = nil
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
