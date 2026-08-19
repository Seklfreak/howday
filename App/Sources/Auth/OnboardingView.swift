import SwiftUI

/// Shown once after first sign-in, while the contacts permission is
/// undecided. There is nothing else to set up: friends, names, and photos
/// all come from the address book.
struct OnboardingView: View {
    let onDone: () -> Void

    @State private var isBusy = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.2.circle")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Find your friends")
                .font(.title.weight(.semibold))
            Text(
                "Moodring is contacts-based: you see each other's moods once you're both "
                    + "in each other's contacts, shown with the name and photo from your "
                    + "address book. Phone numbers are hashed on your device before matching "
                    + "— names and photos never leave your phone."
            )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                allow()
            } label: {
                Text("Allow contacts access")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy)
            Button("Not now") { onDone() }
                .disabled(isBusy)
        }
        .padding(24)
    }

    private func allow() {
        isBusy = true
        Task {
            await ContactDirectory.requestAccess()
            onDone()
        }
    }
}
