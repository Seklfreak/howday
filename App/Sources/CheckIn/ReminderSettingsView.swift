import SwiftUI

struct ReminderSettingsView: View {
    @AppStorage(ReminderScheduler.configuredKey) private var reminderConfigured = false
    @AppStorage(ReminderScheduler.enabledKey) private var reminderEnabled = true
    @AppStorage(ReminderScheduler.windowStartKey) private var windowStart = ReminderScheduler.defaultWindowStart
    @AppStorage(ReminderScheduler.windowEndKey) private var windowEnd = ReminderScheduler.defaultWindowEnd
    @State private var deniedPermission = false
    @State private var applyTask: Task<Void, Never>?
    @State private var applyPending = false

    private static let lastMinute = 23 * 60 + 59

    /// Moving one edge past the other drags the other edge along, keeping
    /// the window at least an hour wide where the day allows.
    private var startBinding: Binding<Date> {
        Binding {
            Self.date(minutes: windowStart)
        } set: { newValue in
            windowStart = Self.minutes(of: newValue)
            if windowEnd <= windowStart { windowEnd = min(windowStart + 60, Self.lastMinute) }
        }
    }

    private var endBinding: Binding<Date> {
        Binding {
            Self.date(minutes: windowEnd)
        } set: { newValue in
            windowEnd = Self.minutes(of: newValue)
            if windowStart >= windowEnd { windowStart = max(windowEnd - 60, 0) }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Daily reminder", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Earliest", selection: startBinding, displayedComponents: .hourAndMinute)
                        DatePicker("Latest", selection: endBinding, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text(
                        "One notification a day asking how you are, at a different time each day "
                            + "somewhere between these two. Scheduled on this device only."
                    )
                }
                if deniedPermission {
                    Section {
                        Text("Notifications are turned off for Howday. Enable them in Settings to get the reminder.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .onAppear { Analytics.screen(.reminder) }
            .onChange(of: reminderEnabled) { scheduleApply() }
            .onChange(of: windowStart) { scheduleApply() }
            .onChange(of: windowEnd) { scheduleApply() }
            .onDisappear {
                // Leaving mid-debounce must not lose the last change.
                applyTask?.cancel()
                if applyPending { Task { await apply() } }
            }
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The wheel picker reports every tick; re-planning 14 notifications per
    /// tick is wasteful, so changes settle for a moment before they're applied.
    private func scheduleApply() {
        applyPending = true
        applyTask?.cancel()
        applyTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await apply()
        }
    }

    private func apply() async {
        applyPending = false
        let enabled = reminderEnabled
        let ok = await ReminderScheduler.sync(enabled: enabled, windowStart: windowStart, windowEnd: windowEnd)
        reminderConfigured = true
        if enabled {
            deniedPermission = !ok
            if ok {
                // Permission granted here also covers friend check-in pushes,
                // which onboarding may have been declined for.
                await PushRegistrar.registerIfAuthorized()
            } else {
                // Same rule as onboarding: a toggle left on while iOS refuses
                // to deliver would be a lie. The message above says why.
                reminderEnabled = false
            }
        }
        Analytics.track(
            "reminder_saved",
            [
                "enabled": String(reminderEnabled),
                "from": String(windowStart / 60),
                "to": String(windowEnd / 60),
            ]
        )
    }

    static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    private static func minutes(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
