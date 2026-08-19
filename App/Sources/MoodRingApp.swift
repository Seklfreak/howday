import Supabase
import SwiftUI

@main
struct MoodRingApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    private enum Stage {
        case loading
        case signedOut
        case onboarding
        case ready
    }

    @State private var stage: Stage = .loading

    var body: some View {
        Group {
            switch stage {
            case .loading:
                ProgressView()
            case .signedOut:
                PhoneSignInView()
            case .onboarding:
                OnboardingView { stage = .ready }
            case .ready:
                MainTabView()
            }
        }
        .task {
            for await state in Supa.client.auth.authStateChanges {
                guard [.initialSession, .signedIn, .signedOut].contains(state.event) else { continue }
                if state.session == nil {
                    stage = .signedOut
                } else {
                    await resolveSignedInStage()
                }
            }
        }
    }

    /// The signup trigger creates the profiles row with an empty display
    /// name; onboarding is done once the user has set one.
    private func resolveSignedInStage() async {
        do {
            let profile = try await ProfileRepository().myProfile()
            stage = profile.displayName.isEmpty ? .onboarding : .ready
        } catch {
            // Profile fetch failed (offline, or trigger not yet applied) —
            // fall through to onboarding, which retries on save.
            stage = .onboarding
        }
    }
}
