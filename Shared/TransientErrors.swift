import Foundation

/// Which failures are worth reacting to rather than reporting. Shared with
/// the widget and notification extensions, so it stays free of Sentry —
/// `Error.report` keeps that, and stays in the app.
extension Error {
    /// True when this error just means the surrounding task was cancelled —
    /// e.g. the user switched tabs while a .task-driven load was in flight.
    /// Never worth showing in the UI: the next appearance restarts the load.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    /// PostgREST rejects a freshly refreshed token whose `iat` is a second
    /// or two ahead of its own clock — skew between Supabase's auth and
    /// PostgREST services, nothing on the device. Transient: a retry after
    /// a short pause succeeds.
    var isJWTClockSkew: Bool {
        localizedDescription.localizedCaseInsensitiveContains("issued at future")
    }

    /// supabase-swift (2.55.3+) drops a token refresh whose starting session
    /// was replaced in the keychain while the request was in flight — meant
    /// for a sign-out racing a refresh, but the widget shares that keychain
    /// item and refreshes on its own. When both find an expired token at
    /// once and the widget stores its result first, the app's refresh throws
    /// this although the session stored now is fresh and valid
    /// (MOODRING-IOS-9). Transient: a second attempt reads that session.
    /// Matched by text because the notification extension links no
    /// Supabase; `ErrorHelpersTests` pins it to the SDK's error.
    var isRefreshDiscarded: Bool {
        localizedDescription.hasPrefix("Token refresh discarded")
    }

    /// The device couldn't reach the network — backgrounded mid-request, no
    /// signal, DNS or the connection dropped. Worth showing the user (the load
    /// really did fail) but never worth a Sentry issue: there is no defect to
    /// find, and one issue per blip is how a project fills with noise. The
    /// board load is the usual source, cut off with ECONNRESET when the app
    /// goes to the background mid-request.
    var isTransientNetwork: Bool {
        let nsError = self as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorCallIsActive,
            NSURLErrorDataNotAllowed,
        ].contains(nsError.code)
    }
}

/// Runs `operation`, retrying once if it fails with the transient PostgREST
/// clock-skew error (after a short pause; see `isJWTClockSkew`) or with a
/// token refresh another process beat it to (at once; see
/// `isRefreshDiscarded`). The retry after a discarded refresh may itself
/// meet clock skew — it runs on the token the widget just minted — so it
/// gets the skew retry as well, but never a second discarded-refresh one.
func withSkewRetry<T>(_ operation: () async throws -> T) async throws -> T {
    do {
        return try await retryingClockSkew(operation)
    } catch where error.isRefreshDiscarded {
        return try await retryingClockSkew(operation)
    }
}

private func retryingClockSkew<T>(_ operation: () async throws -> T) async throws -> T {
    do {
        return try await operation()
    } catch where error.isJWTClockSkew {
        try await Task.sleep(for: .seconds(2))
        return try await operation()
    }
}
