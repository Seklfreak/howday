import ContactsUI
import Supabase
import SwiftUI
import UIKit
import WidgetKit

/// The friends board, embedded below the mood bar on the home screen.
/// HomeView only mounts it once today's check-in exists, so the old
/// "check in first" gate lives there now — the picker IS the gate.
struct BoardView<Header: View>: View {
    /// Rendered inside the scroll view, above the grid. The mood bar lives
    /// here rather than above BoardView so that a pull-to-refresh drags the
    /// whole screen down together — pinned while the board slid out from
    /// under it, it read as the screen coming apart.
    @ViewBuilder let header: Header

    @Environment(\.scenePhase) private var scenePhase
    @State private var board = BoardState()
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var contactsDenied = false
    /// Set while contacts access is iOS 18 "limited": how many contacts the
    /// app can see, for the banner offering to add more. nil otherwise.
    @State private var limitedContactCount: Int?
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        ScrollView {
            header
            if isLoading {
                ProgressView().padding(.top, 48)
            } else if contactsDenied {
                contactsPrompt
            } else {
                grid
            }
        }
        .task { await listenForChanges() }
        .refreshable { await load(forceSync: true) }
        .onChange(of: scenePhase) {
            // Coming back to the foreground: the socket may have dropped
            // and missed events are never replayed — refetch. This is
            // also what makes a notification tap land on fresh data.
            if scenePhase == .active {
                Task { await load() }
            }
        }
    }

    private var contactsPrompt: some View {
        ContentUnavailableView {
            Label("Contacts access is off", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("Howday is contacts-based — friends appear automatically when you're in each other's contacts.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        // Same reason as the empty-board state: centred inside a scroll view
        // it would otherwise collapse to its intrinsic height.
        .frame(minHeight: 320)
    }

    @ViewBuilder
    private var grid: some View {
        if #available(iOS 18, *), let limitedContactCount {
            LimitedContactsBanner(count: limitedContactCount) {
                // The picker's completion runs before CNContactStoreDidChange
                // lands; mark the index stale by hand so this reload reads
                // the newly shared contacts rather than the cached sweep.
                await ContactDirectory.noteAddressBookChanged()
                await load(forceSync: true)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        // The minimum card width grows with the text, so the grid drops to
        // one column at the accessibility sizes instead of squeezing names.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150 * TypeScale.clamp(scale)), spacing: 12)], spacing: 12) {
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
            // ContentUnavailableView centres itself in the space it is
            // given, and inside a scroll view that is only its own height.
            .frame(minHeight: 280)
        }
        if let errorMessage {
            Text(errorMessage).foregroundStyle(.red).font(.footnote)
        }
    }

    private func load(forceSync: Bool = false) async {
        // First board visit triggers the contacts prompt; afterwards this is
        // a no-op and isAuthorized reflects the user's answer.
        let wasAsked = ContactDirectory.hasBeenAsked
        await ContactDirectory.requestAccess()
        contactsDenied = !ContactDirectory.isAuthorized
        // Reported here as well as in onboarding: whichever call actually
        // raises the prompt is the one that sees the answer.
        if !wasAsked {
            Analytics.track(ContactDirectory.isAuthorized ? "contacts_allowed" : "contacts_declined")
        }
        if !contactsDenied {
            // Read before the fetch, so the banner is there the moment the
            // grid is: the index this counts is the one fetchMutuals needs
            // anyway, so it costs nothing extra.
            limitedContactCount = ContactDirectory.isLimited ? await ContactDirectory.visibleContactCount() : nil
            // Never awaited, forced or not. The board renders from the links
            // the previous sync established, so waiting bought nothing and
            // cost the upload's round trip (1.4s at p50, 3s at p95) — and on
            // a pull-to-refresh that round trip, plus the address-book sweep
            // behind it, was held under the refresh control. That is what
            // made the pull feel broken: a spinner stuck for seconds with
            // contact I/O fighting the animation for the CPU.
            //
            // `forceSync` still guarantees the upload happens (it ignores
            // the fingerprint, which is what re-links a contact who signed
            // up since the last one); the board just picks it up when it
            // lands rather than blocking the gesture on it.
            Task { if await ContactDirectory.syncIfNeeded(force: forceSync) { await fetch() } }
            await fetch()
        }
        isLoading = false
    }

    private func fetch() async {
        do {
            board = try await withTrace("board.load") { try await withSkewRetry { try await BoardRepository().load() } }
            errorMessage = nil
            // Whatever the board just learned, the widget should show too.
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Leaving the tab cancels the .task mid-request; don't show
            // that as an error — reappearing restarts the load anyway.
            guard !error.isCancellation else { return }
            errorMessage = error.report("board.load")
        }
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
        defer { Task { await Supa.client.removeChannel(channel) } }
        // Initial load AFTER subscribing: there is no realtime catch-up, so
        // a check-in landing mid-load would otherwise stay invisible until
        // the next manual refresh. But not *only* after: offline, subscribe
        // never returns, and the board sat on a spinner behind a parked
        // check-in. So it gets a moment; past that the board loads anyway
        // and refetches once the socket does come up, which is the
        // catch-up the ordering exists for.
        let subscribing = Task { await channel.subscribe() }
        let subscribedInTime = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await subscribing.value; return true }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        await load()
        if !subscribedInTime {
            await subscribing.value
            await fetch()
        }
        for await _ in changes {
            await load()
        }
    }
}

/// "Howday can see 3 contacts — add more": the way back to a full board for
/// someone who chose "Select Contacts" on the system prompt. The picker is
/// the system's own; the app never sees the address book beyond what it
/// returns. Only the count is shown — there is no way to know the total.
@available(iOS 18, *)
private struct LimitedContactsBanner: View {
    let count: Int
    /// Runs after the picker closes with at least one contact added.
    let onAdded: () async -> Void

    @State private var showPicker = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Howday can see \(count) contact\(count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.medium))
                Text("Friends outside that selection stay hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Add more") {
                Analytics.track("contacts_add_more")
                showPicker = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.07))
        }
        .contactAccessPicker(isPresented: $showPicker) { added in
            guard !added.isEmpty else { return }
            Task { await onAdded() }
        }
    }
}

private struct BoardCard: View {
    let entry: BoardEntry

    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    private var avatarSize: CGFloat { 56 * TypeScale.clamp(scale) }
    private var badgeSize: CGFloat { 28 * TypeScale.clamp(scale) }

    /// Tapping a friend starts a chat with them. sms: goes to the system's
    /// default messaging app (user-selectable since iOS 18.2), so this lands
    /// in whatever chat app the user actually uses for that person's number.
    private var messageURL: URL? {
        guard let phone = entry.identity.phone else { return nil }
        let dialable = phone.filter { $0.isNumber || $0 == "+" }
        guard !dialable.isEmpty else { return nil }
        return URL(string: "sms:\(dialable)")
    }

    var body: some View {
        if let messageURL {
            Button {
                Analytics.track("friend_tapped")
                UIApplication.shared.open(messageURL)
            } label: {
                card
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens a chat with \(entry.identity.name)")
        } else {
            card
        }
    }

    /// The friend's mood-ring color — nil until they've checked in today,
    /// which renders as a ring that's "off".
    private var ringTheme: MoodTheme? {
        entry.checkin.map { MoodTheme.forEmoji($0.emoji) }
    }

    private var card: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                avatar
                    .padding(4)
                    .overlay {
                        Circle().strokeBorder(ringTheme?.accent ?? .white.opacity(0.16), lineWidth: 2.5)
                    }
                    .shadow(color: ringTheme?.accent.opacity(0.5) ?? .clear, radius: 8)
                if let emoji = entry.checkin?.emoji {
                    // 16 in 28: a square emoji's diagonal stays inside the
                    // round badge instead of touching its edge.
                    Text(emoji)
                        .font(.system(size: 16 * TypeScale.clamp(scale)))
                        .frame(width: badgeSize, height: badgeSize)
                        .background(Circle().fill(Color(red: 0.13, green: 0.12, blue: 0.17)))
                        .offset(x: 5, y: 5)
                }
            }
            Text(entry.identity.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            // Kept even when there's nothing to say: the grid sizes each
            // card to its own content, so dropping the line made checked-in
            // friends' cards visibly shorter than the rest.
            Text(entry.checkin == nil ? "Not yet" : " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(entry.checkin != nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.07))
        }
    }

    /// The contact's photo from the viewer's address book, or a monogram.
    /// Already decoded by ContactDirectory — never decode in a body.
    @ViewBuilder
    private var avatar: some View {
        if let avatar = entry.identity.avatar {
            Image(uiImage: avatar.image)
                .resizable()
                .scaledToFill()
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: avatarSize, height: avatarSize)
                Text(entry.identity.name.prefix(1).uppercased())
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
