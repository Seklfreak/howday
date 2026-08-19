import SwiftUI

/// Shown once after first sign-in, until a display name is saved.
struct OnboardingView: View {
    let onDone: () -> Void

    @State private var name = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textContentType(.givenName)
                } footer: {
                    Text("This is what your friends see next to your mood.")
                }
                Section {
                    Button(action: save) {
                        if isBusy { ProgressView() } else { Text("Continue") }
                    }
                    .disabled(isBusy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Welcome")
        }
    }

    private func save() {
        errorMessage = nil
        isBusy = true
        Task {
            do {
                try await ProfileRepository().updateDisplayName(name.trimmingCharacters(in: .whitespaces))
                onDone()
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }
}
