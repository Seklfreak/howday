import Foundation

enum AppConfig {
    static var supabaseURL: URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: raw), url.host != nil else {
            fatalError("SUPABASE_URL missing — copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig and fill it in")
        }
        return url
    }

    static var supabaseAnonKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String, !key.isEmpty else {
            fatalError("SUPABASE_ANON_KEY missing — copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig and fill it in")
        }
        return key
    }

    /// Optional — empty/missing disables crash reporting (simulator and CI
    /// builds run from the placeholder xcconfig, which leaves it blank).
    static var sentryDSN: String? {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String, !dsn.isEmpty else {
            return nil
        }
        return dsn
    }

    /// Marketing version and build, as "1.27.0 (412)". Shown in Settings
    /// beside the user id: a bug report from TestFlight is close to useless
    /// without knowing which build made it. Locally this reads the
    /// placeholders in `project.yml`; CI passes the real pair on the
    /// `xcodebuild` command line.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    /// The install link the invite sheet hands out. Optional in the same way
    /// as the Sentry DSN: a build without it hides the invite rather than
    /// sharing a link that goes nowhere.
    /// The two documents Settings links to. Fixed rather than configured:
    /// they are the app's own site, the App Store listing points at the same
    /// pages, and a build with the links blanked would be worse than one
    /// with them wrong.
    static let privacyPolicyURL = URL(string: "https://howday.app/privacy-policy/")!
    static let termsURL = URL(string: "https://howday.app/terms/")!

    static var inviteURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "INVITE_URL") as? String,
              let url = URL(string: raw), url.host != nil else {
            return nil
        }
        return url
    }
}
