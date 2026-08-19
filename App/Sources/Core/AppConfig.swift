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
}
