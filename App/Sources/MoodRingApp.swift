import Sentry
import Supabase
import SwiftUI

@main
struct MoodRingApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate

    init() {
        // Debug builds stay quiet — local runs would drown real crash
        // reports, and the placeholder xcconfig has no DSN anyway.
        #if !DEBUG
        if let dsn = AppConfig.sentryDSN {
            SentrySDK.start { options in
                options.dsn = dsn
                // Tracing: every withTrace flow becomes a transaction with
                // per-request Supabase spans (automatic network tracking),
                // and failed-request capture (on by default) reports 5xx
                // responses. Full sampling is fine at this user count —
                // dial down before it ever dents the Sentry quota.
                options.tracesSampleRate = 1.0
                // Failed-request capture defaults to 5xx only; Supabase
                // reports auth/RLS/PostgREST problems as 4xx, and those
                // are exactly the ones worth seeing.
                options.failedRequestStatusCodes = [HttpStatusCodeRange(min: 400, max: 599)]
            }
        }
        // Same rule as Sentry: local runs would only muddy the numbers, and
        // the placeholder xcconfig has no Umami credentials anyway.
        Analytics.configure()
        #endif
    }

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
                HomeView()
            }
        }
        .fontDesign(.rounded)
        .tint(MoodTheme.brand.accent)
        .onChange(of: stage) {
            // Every launch that reaches the signed-in UI re-registers, so a
            // rotated APNs token is re-uploaded without any bookkeeping.
            if stage == .ready {
                Task { await PushRegistrar.register() }
            }
        }
        .task {
            for await state in Supa.client.auth.authStateChanges {
                guard [.initialSession, .signedIn, .signedOut].contains(state.event) else { continue }
                if state.session == nil {
                    stage = .signedOut
                } else {
                    // Onboarding is just the contacts pitch — once the
                    // permission prompt has been answered either way, there
                    // is nothing left to set up.
                    stage = ContactDirectory.hasBeenAsked ? .ready : .onboarding
                }
            }
        }
    }
}
