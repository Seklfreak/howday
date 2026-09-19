import Foundation
import Supabase

enum Supa {
    static let client = SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseAnonKey,
        options: SupabaseClientOptions(
            auth: .init(
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
