import Sentry

enum CrashReporting {
    /// The options the app starts Sentry with. Kept out of `HowdayApp` so
    /// `CrashReportingTests` can start the SDK exactly the way a release
    /// build does — Debug builds never start it, so without that test no
    /// run before TestFlight ever takes an event through the SDK.
    static func configure(_ options: Options, dsn: String) {
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
        // Off: the SDK never sees a watchdog kill, it infers one on
        // the next launch by elimination — no crash recorded, not
        // backgrounded, no upgrade, no reboot — which is also exactly
        // what swiping the app out of the app switcher looks like.
        // Every report so far has been one event per tester per
        // build, scattered, where a real memory problem repeats for
        // the same person; and the app runs at around 37 MB, which
        // is not a size anything gets killed for. If real numbers
        // are ever wanted they come from MetricKit's
        // MXAppExitMetric, which counts memory-limit exits the OS
        // actually performed, rather than from a guess here.
        options.enableWatchdogTerminationTracking = false
    }
}
