import UIKit

@MainActor
final class PushDelegate: NSObject, UIApplicationDelegate {
    weak var notifications: TeamNotifications?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await notifications?.registerRemoteToken(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        notifications?.remoteRegistered = false
        notifications?.remoteStatus = "iOS push registration failed: " + error.localizedDescription
    }
}

enum SigningProfile {
    static func pushEnvironment() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)), end.upperBound > start.lowerBound,
              let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil),
              let dictionary = plist as? [String: Any], let entitlements = dictionary["Entitlements"] as? [String: Any],
              let environment = entitlements["aps-environment"] as? String,
              ["development", "production"].contains(environment) else { return nil }
        return environment
    }
}
