import Supabase
import SwiftUI
import UserNotifications

/// App delegate hook for APNs: receives the device token, hands it to
/// PushRegistrar, and keeps friend-check-in banners visible while the app
/// is foregrounded.
final class PushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await PushRegistrar.upload(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected on simulators without APNs support — nothing actionable.
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// rpc bodies for register/unregister_device_token.
private struct RegisterParams: Encodable {
    let deviceToken: String
    let isSandbox: Bool
    enum CodingKeys: String, CodingKey {
        case deviceToken = "device_token"
        case isSandbox = "is_sandbox"
    }
}

private struct UnregisterParams: Encodable {
    let deviceToken: String
    enum CodingKeys: String, CodingKey {
        case deviceToken = "device_token"
    }
}

/// Registers this device for friend-check-in pushes: requests an APNs token
/// on every launch that reaches the signed-in UI and stores it server-side
/// (device_tokens) keyed to the current user.
enum PushRegistrar {
    private static let tokenKey = "apnsDeviceToken"

    /// Request an APNs token if notifications are already allowed;
    /// PushDelegate uploads whatever comes back. Deliberately never raises
    /// the system prompt — that belongs to the onboarding screen that has
    /// just explained what the notifications are for. Called on every launch
    /// that reaches the signed-in UI, so permission granted later in iOS
    /// Settings is picked up too.
    static func registerIfAuthorized() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }

    static func upload(_ token: String) async {
        guard (try? await Supa.client.auth.session) != nil else { return }
        // Must mirror the aps-environment entitlement: Debug builds get
        // sandbox APNs tokens, Release (TestFlight/App Store) production —
        // a token only works against the environment that issued it.
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        do {
            try await Supa.client
                .rpc("register_device_token", params: RegisterParams(deviceToken: token, isSandbox: sandbox))
                .execute()
            UserDefaults.standard.set(token, forKey: tokenKey)
        } catch {
            // The next launch retries; a missing token just means no pushes.
        }
    }

    /// Sign-out path: drop the server row so a signed-out device gets nothing.
    static func unregister() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        _ = try? await Supa.client
            .rpc("unregister_device_token", params: UnregisterParams(deviceToken: token))
            .execute()
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }
}
