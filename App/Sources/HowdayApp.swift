import Sentry
import Supabase
import SwiftUI

@main
struct HowdayApp: App {
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
                // A widget hands the app the source it was tapped from;
                // nothing else uses the scheme, so an unknown URL is
                // simply ignored rather than routed.
                .onOpenURL { url in
                    guard let source = WidgetSource.from(openURL: url) else { return }
                    Analytics.track("widget_opened", ["source": source.rawValue])
                }
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

    @Environment(\.scenePhase) private var scenePhase
    @State private var stage: Stage = .loading
    /// Set once the onboarding screens have been walked through. Without it
    /// a "Not now" on the contacts prompt leaves the system permission
    /// undecided, and onboarding reappears on every launch.
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false

    var body: some View {
        Group {
            switch stage {
            case .loading:
                ProgressView()
            case .signedOut:
                PhoneSignInView()
            case .onboarding:
                OnboardingView {
                    onboardingCompleted = true
                    stage = .ready
                }
            case .ready:
                HomeView()
            }
        }
        .fontDesign(.rounded)
        .tint(MoodTheme.brand.accent)
        .onChange(of: stage) {
            // The widgets show whoever is signed in — or nothing. A sign-out
            // must blank them now, not at their next half-hourly refresh,
            // and a sign-in should fill them without waiting for the board.
            if stage == .signedOut { WidgetSync.signedOut() }
            if stage == .ready { WidgetSync.invalidate() }
            // Every launch that reaches the signed-in UI re-registers, so a
            // rotated APNs token is re-uploaded without any bookkeeping.
            if stage == .ready {
                Task { await PushRegistrar.registerIfAuthorized() }
                // Contacts used to sync only from the board, which HomeView
                // mounts only once today's check-in exists — so somebody who
                // signed up and didn't check in had never uploaded anything
                // and was invisible to everyone, permanently. Reaching the
                // signed-in UI is the honest trigger; it also covers the
                // cold launch, which fires no willEnterForeground.
                Task { await ContactDirectory.syncIfNeeded() }
            }
        }
        .onChange(of: scenePhase) {
            // The daily reminder is booked a fortnight ahead, one random
            // time per day; every foreground extends the plan. Never prompts.
            if scenePhase == .active {
                Task { await ReminderScheduler.topUp() }
            }
        }
        .task {
            for await state in Supa.client.auth.authStateChanges {
                guard [.initialSession, .signedIn, .signedOut].contains(state.event) else { continue }
                if state.session == nil {
                    stage = .signedOut
                } else {
                    // Onboarding is the contacts and notifications pitch;
                    // an already-answered contacts prompt means an install
                    // from before the flag existed.
                    stage = (onboardingCompleted || ContactDirectory.hasBeenAsked) ? .ready : .onboarding
                }
            }
        }
    }
}
