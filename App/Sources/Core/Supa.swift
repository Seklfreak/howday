import Foundation
import Supabase

enum Supa {
    static let client = SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseAnonKey,
        options: SupabaseClientOptions(
            auth: .init(
                storage: SessionKeychain(),
                // Hand the stored session to RootView as-is and refresh it
                // in the background. The default first *refreshes* and
                // emits nil when that fails — so an hour-old token with no
                // network (a tunnel, airplane mode) landed on the sign-in
                // screen, and a parked check-in never got the chance to be
                // retried. supabase-swift itself calls the default
                // behaviour incorrect and plans to flip it.
                emitLocalSessionAsInitialSession: true
            )
        )
    )
}

/// The SDK's own keychain storage, except that an app extension can never
/// delete the session. The widget shares the app's keychain item, and when
/// one of its refreshes is refused the SDK wipes that item and announces
/// `signedOut` — inside the widget's process, where nobody is listening.
/// The app kept showing the board and every request after that failed with
/// "Auth session missing." (MOODRING-IOS-7). Signing out belongs to the
/// app: if the session really is dead, the app's own next refresh is
/// refused too, and that removal happens where RootView hears about it.
struct SessionKeychain: AuthLocalStorage {
    private let keychain = KeychainLocalStorage()
    private let isExtension = Bundle.main.bundleURL.pathExtension == "appex"

    func store(key: String, value: Data) throws {
        try keychain.store(key: key, value: value)
    }

    func retrieve(key: String) throws -> Data? {
        try keychain.retrieve(key: key)
    }

    func remove(key: String) throws {
        guard !isExtension else { return }
        try keychain.remove(key: key)
    }
}
