import Foundation
import Observation
import UserNotifications
import UIKit

struct TeamNotice: Codable, Identifiable, Hashable {
    var id: String
    var agentId: String
    var agentLabel: String
    var kind: String
    var title: String
    var detail: String
    var time: String?
    var read = false
}

struct NoticeLedger: Codable {
    var initialized = false
    var observed: [String: String] = [:]
    var notices: [TeamNotice] = []

    mutating func consume(_ agents: [Agent]) -> [TeamNotice] {
        guard !agents.isEmpty else { return [] }
        var fresh: [TeamNotice] = []
        for agent in agents {
            let status = agent.taskStatus
            guard let id = status.eventId,
                  ["completed", "failed", "interrupted", "needs_input"].contains(status.kind) else { continue }
            guard observed[agent.id] != id else { continue }
            observed[agent.id] = id
            // The relay's continuous work finishes many times an hour; only tasks Kewz sent are news.
            if status.kind == "completed" && !Self.isKewzRun(status.runId) { continue }
            guard initialized, !notices.contains(where: { $0.id == id }) else { continue }
            let notice = TeamNotice(id: id, agentId: agent.id, agentLabel: agent.displayName, kind: status.kind,
                                    title: status.label, detail: status.detail ?? "Open the conversation for details.", time: status.at)
            fresh.append(notice)
        }
        initialized = true
        notices = Array((Array(fresh.reversed()) + notices).prefix(60))
        return fresh
    }

    /// Messages Kewz sends get UUID ids; relay requests use stable p-/c- ids.
    static func isKewzRun(_ id: String?) -> Bool {
        guard let id else { return false }
        return id.range(of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-", options: .regularExpression) != nil
    }
}

@MainActor
@Observable
final class TeamNotifications: NSObject, UNUserNotificationCenterDelegate {
    var ledger = NoticeLedger()
    var enabled = UserDefaults.standard.bool(forKey: "teamroom.alerts.enabled")
    var authorization = "Not requested"
    var permissionError: String?
    var remoteStatus = "Push setup not checked"
    var remoteRegistered = false
    var signingStatus = "Not checked"
    var client: TeamRoomClient?
    var openAgent: ((String) -> Void)?
    private var storageKey = ""
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    var unreadCount: Int { ledger.notices.filter { !$0.read }.count }

    func configure(server: String) {
        let key = "teamroom.notice-ledger." + server
        guard key != storageKey else { return }
        storageKey = key
        ledger = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(NoticeLedger.self, from: $0) } ?? NoticeLedger()
        Task { await refreshPermission() }
    }

    func observe(_ agents: [Agent]) {
        let fresh = ledger.consume(agents)
        persist()
        guard enabled else { return }
        if remoteRegistered { updateBadge(); return }
        for notice in fresh {
            Task { await deliver(notice) }
        }
        updateBadge()
    }

    func enable() async {
        permissionError = nil
        do {
            enabled = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            UserDefaults.standard.set(enabled, forKey: "teamroom.alerts.enabled")
            await refreshPermission()
            await refreshPush(register: enabled)
            updateBadge()
        } catch { permissionError = error.localizedDescription }
    }

    func disable() {
        enabled = false
        UserDefaults.standard.set(false, forKey: "teamroom.alerts.enabled")
        center.removeAllPendingNotificationRequests()
        remoteRegistered = false
        Task { await client?.unregisterPush() }
        Task { try? await center.setBadgeCount(0) }
    }

    func refreshPermission() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: authorization = "Allowed"
        case .provisional, .ephemeral: authorization = "Quiet delivery"
        case .denied:
            authorization = "Disabled in iPhone Settings"
            enabled = false
            UserDefaults.standard.set(false, forKey: "teamroom.alerts.enabled")
        case .notDetermined: authorization = "Not requested"
        @unknown default: authorization = "Unknown"
        }
    }

    func refreshPush(register: Bool = false) async {
        let environment = SigningProfile.pushEnvironment()
        signingStatus = environment.map { "Profile permits \($0) push" } ?? "Will verify with iOS during registration"
        guard let client else { remoteStatus = "Connect to the Team Room first"; return }
        do {
            let status = try await client.pushStatus()
            if !status.configured { remoteStatus = status.reason ?? "APNs server setup required"; remoteRegistered = false }
            if register && enabled {
                if status.configured { remoteStatus = "Registering this iPhone…" }
                UIApplication.shared.registerForRemoteNotifications()
            } else if status.configured { remoteStatus = status.registered == true ? "Device registered" : "Enable alerts to register this iPhone" }
        } catch { remoteStatus = "Push server unavailable: " + error.localizedDescription }
    }

    func registerRemoteToken(_ token: String) async {
        guard enabled, let client else { return }
        let environment = SigningProfile.pushEnvironment() ?? "production"
        signingStatus = "iOS accepted push registration"
        do {
            try await client.registerPush(token: token, environment: environment)
            remoteRegistered = true
            remoteStatus = "Registered for background alerts"
        } catch { remoteRegistered = false; remoteStatus = error.localizedDescription }
    }

    func testRemotePush() async {
        do { try await client?.testPush() }
        catch { permissionError = error.localizedDescription }
    }

    func sendTest() async {
        await deliver(TeamNotice(id: "test-" + UUID().uuidString, agentId: "", agentLabel: "Team Room",
                                 kind: "test", title: "Alerts are enabled", detail: "Test notification", time: nil))
    }

    func markRead(agentId: String? = nil) {
        for index in ledger.notices.indices where agentId == nil || ledger.notices[index].agentId == agentId {
            ledger.notices[index].read = true
        }
        persist()
        updateBadge()
    }

    private func persist() {
        guard !storageKey.isEmpty, let data = try? JSONEncoder().encode(ledger) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func updateBadge() {
        guard enabled else { return }
        let count = unreadCount
        Task { try? await center.setBadgeCount(count) }
    }

    private func deliver(_ notice: TeamNotice) async {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = notice.agentLabel + ": " + notice.title
        content.body = notice.kind == "test" ? "Team Room can show alerts while connected." : String(notice.detail.prefix(180))
        content.sound = .default
        content.userInfo = ["agentId": notice.agentId]
        content.threadIdentifier = notice.agentId
        let request = UNNotificationRequest(identifier: notice.id, content: content, trigger: nil)
        do { try await center.add(request) } catch { permissionError = error.localizedDescription }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["agentId"] as? String
        Task { @MainActor [weak self] in
            if let id, !id.isEmpty { self?.openAgent?(id) }
        }
        completionHandler()
    }
}
