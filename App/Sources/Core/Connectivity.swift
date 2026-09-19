import Foundation
import Network

/// Network reachability, for retrying a parked check-in the moment the
/// tunnel ends rather than on the next foreground. Deliberately not used to
/// *prevent* requests — a "satisfied" path can still fail, and an
/// "unsatisfied" one is occasionally wrong; the requests themselves decide
/// what happened, this only says when trying again is worth it.
enum Connectivity {
    /// Yields once per transition from unreachable to reachable. The
    /// monitor's first report (the current state) never yields, so a
    /// subscriber that is already online is not told to retry on start.
    static func regained() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            // The handler is the only reader of this flag and NWPathMonitor
            // calls it serially on its queue, so a plain box is safe here.
            let state = ReachabilityBox()
            monitor.pathUpdateHandler = { path in
                let reachable = path.status == .satisfied
                if reachable, state.wasReachable == false { continuation.yield() }
                state.wasReachable = reachable
            }
            monitor.start(queue: DispatchQueue(label: "howday.connectivity"))
            continuation.onTermination = { _ in monitor.cancel() }
        }
    }

    private final class ReachabilityBox: @unchecked Sendable {
        /// nil until the first report, which is the current state and not
        /// a transition.
        var wasReachable: Bool?
    }
}
