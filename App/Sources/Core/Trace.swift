import Sentry

/// Wraps an async flow in a Sentry transaction so its duration — and the
/// Supabase HTTP requests inside it, captured as child spans by Sentry's
/// automatic network tracking — shows up under a stable name in the
/// Performance view. A no-op when the SDK isn't started (Debug builds) or
/// the trace is sampled out.
func withTrace<T>(_ name: String, _ operation: () async throws -> T) async rethrows -> T {
    // bindToScope is what parents the network spans to this transaction.
    let transaction = SentrySDK.startTransaction(name: name, operation: "app.flow", bindToScope: true)
    do {
        let result = try await operation()
        transaction.finish()
        return result
    } catch {
        transaction.finish(status: .internalError)
        throw error
    }
}
