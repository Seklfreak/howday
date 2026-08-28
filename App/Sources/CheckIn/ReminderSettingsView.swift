import SwiftUI

struct ReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("reminderConfigured") private var reminderConfigured = false
    @AppStorage("reminderEnabled") private var reminderEnabled = true
    @AppStorage("reminderHour") private var reminderHour = 20
    @AppStorage("reminderMinute") private var reminderMinute = 0
    @State private var deniedPermission = false

    private var timeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: .now
            ) ?? .now
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = parts.hour ?? 20
            reminderMinute = parts.minute ?? 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Daily reminder", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("One notification a day asking how you are. Scheduled on this device only.")
                }
                if deniedPermission {
                    Section {
                        Text("Notifications are turned off for Howday. Enable them in Settings to get the reminder.")
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Button("Save") {
                        Task {
                            let ok = await ReminderScheduler.sync(
                                enabled: reminderEnabled, hour: reminderHour, minute: reminderMinute
                            )
                            deniedPermission = !ok
                            if ok {
                                reminderConfigured = true
                                // Permission granted here also covers friend
                                // check-in pushes, which onboarding may have
                                // been declined for.
                                await PushRegistrar.registerIfAuthorized()
                                Analytics.track(
                                    "reminder_saved",
                                    ["enabled": String(reminderEnabled), "hour": String(reminderHour)]
                                )
                                dismiss()
                            }
                        }
                    }
                }
            }
            .onAppear { Analytics.screen(.reminder) }
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
