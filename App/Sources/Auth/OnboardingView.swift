import SwiftUI

/// Shown once after first sign-in: the contacts pitch (that's the whole
/// social graph — friends, names, and photos all come from the address book)
/// followed by the notifications pitch. Each system prompt is raised from a
/// screen that has just explained what it's for, and never two at once.
struct OnboardingView: View {
    let onDone: () -> Void

    private enum Step {
        case contacts
        case notifications
    }

    @State private var step: Step = .contacts
    @State private var isBusy = false
    @AppStorage(ReminderScheduler.configuredKey) private var reminderConfigured = false
    @AppStorage(ReminderScheduler.enabledKey) private var reminderEnabled = true
    @AppStorage(ReminderScheduler.windowStartKey) private var windowStart = ReminderScheduler.defaultWindowStart
    @AppStorage(ReminderScheduler.windowEndKey) private var windowEnd = ReminderScheduler.defaultWindowEnd

    var body: some View {
        ZStack {
            MoodBackground(theme: .brand)
            switch step {
            case .contacts: contacts
            case .notifications: notifications
            }
        }
        .tint(MoodTheme.brand.accent)
    }

    private var contacts: some View {
        page(
            symbol: "person.2.circle",
            title: "Find your friends",
            body: "You see each other's moods once you're both in each other's contacts — nothing to add, "
                + "no usernames. Numbers are hashed on your device before matching; names and photos never "
                + "leave your phone.",
            action: "Allow contacts access",
            perform: allowContacts
        )
        .onAppear { Analytics.screen(.onboarding) }
    }

    private var notifications: some View {
        page(
            symbol: "bell.circle",
            title: "Never miss a day",
            body: "A nudge to check in at a different time each day, \(windowText), "
                + "and a heads-up when a friend's ring changes. "
                + "Both are off in Settings any time, and the hours are yours to pick.",
            action: "Turn on notifications",
            perform: allowNotifications
        )
        .onAppear { Analytics.screen(.notifications) }
    }

    private func page(
        symbol: String,
        title: String,
        body text: String,
        action: String,
        perform: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title.weight(.semibold))
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: perform) {
                Text(action).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy)
            Button("Not now") { advance(skipped: true) }
                .disabled(isBusy)
        }
        .padding(24)
    }

    private var windowText: String {
        let from = ReminderSettingsView.date(minutes: windowStart).formatted(date: .omitted, time: .shortened)
        let to = ReminderSettingsView.date(minutes: windowEnd).formatted(date: .omitted, time: .shortened)
        return "between \(from) and \(to)"
    }

    private func allowContacts() {
        isBusy = true
        Task {
            // Only report when this call is the one that raised the prompt —
            // requestAccess is a no-op once the user has answered.
            let wasAsked = ContactDirectory.hasBeenAsked
            await ContactDirectory.requestAccess()
            if !wasAsked {
                Analytics.track(ContactDirectory.isAuthorized ? "contacts_allowed" : "contacts_declined")
            }
            advance(skipped: false)
        }
    }

    private func allowNotifications() {
        isBusy = true
        Task {
            // One prompt covers both: the local daily reminder and the push
            // about a friend's check-in ask for the same authorization.
            let granted = await ReminderScheduler.sync(
                enabled: true, windowStart: windowStart, windowEnd: windowEnd
            )
            reminderConfigured = true
            // A toggle left "on" while iOS refuses to deliver would be a lie;
            // Settings shows what's actually scheduled.
            reminderEnabled = granted
            Analytics.track(granted ? "notifications_allowed" : "notifications_declined")
            if granted { await PushRegistrar.registerIfAuthorized() }
            advance(skipped: false)
        }
    }

    private func advance(skipped: Bool) {
        switch step {
        case .contacts:
            if skipped { Analytics.track("onboarding_skipped") }
            isBusy = false
            withAnimation { step = .notifications }
        case .notifications:
            if skipped { Analytics.track("notifications_skipped") }
            onDone()
        }
    }
}
