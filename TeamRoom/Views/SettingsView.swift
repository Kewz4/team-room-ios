import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var deviceLink: DeviceLink?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Server", value: model.baseURLString)
                    LabeledContent("Live socket", value: model.socketNote)
                    if let lastSync = model.lastSync {
                        LabeledContent("Last sync", value: lastSync.formatted(date: .omitted, time: .standard))
                    }
                    Button("Refresh now") { model.refresh() }
                    Button("Recheck runners") { Task { await model.checkRunners() } }
                }

                Section("Teammates") {
                    ForEach(model.agents) { agent in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                BrandIcon(provider: agent.provider ?? "")
                                    .frame(width: 16, height: 16)
                                Text(agent.label)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(agent.taskStatus.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(agent.modelLabel ?? "") · \(agent.account ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(usageLine(agent))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section {
                    LabeledContent("iPhone permission", value: model.notifications.authorization)
                    Toggle("iPhone notifications", isOn: Binding(
                        get: { model.notifications.enabled },
                        set: { value in
                            if value { Task { await model.notifications.enable() } }
                            else { model.notifications.disable() }
                        }))
                    if model.notifications.enabled {
                        Button("Test local alert") { Task { await model.notifications.sendTest() } }
                    }
                    LabeledContent("Signing profile", value: model.notifications.signingStatus)
                    LabeledContent("Background delivery", value: model.notifications.remoteStatus)
                    Button("Recheck push setup") { Task { await model.notifications.refreshPush(register: model.notifications.enabled) } }
                    if model.notifications.remoteRegistered {
                        Button("Test background push") { Task { await model.notifications.testRemotePush() } }
                    }
                    Button("Open iPhone notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    if let error = model.notifications.permissionError {
                        Text(error).foregroundStyle(Tokens.failure)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Notifications cover finished tasks, failures and requests for input. Background delivery needs a push-enabled signing profile and APNs server credentials. Until both are configured, alerts arrive while Team Room is open and the inbox catches up when you return.")
                }

                Section("Devices") {
                    Button {
                        Task {
                            deviceLink = await model.createDeviceLink()
                            copied = false
                        }
                    } label: {
                        Label("Create a device link", systemImage: "link")
                    }
                    if let link = deviceLink?.url ?? deviceLink?.localUrl {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(link)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Button(copied ? "Copied" : "Copy link") {
                                UIPasteboard.general.string = link
                                copied = true
                            }
                            .font(.caption)
                        }
                    }
                }

                Section {
                    Button("Sign out this device", role: .destructive) {
                        model.signOut()
                        dismiss()
                    }
                } footer: {
                    Text("Team Room \(appVersion) — private client for the local bridge.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func usageLine(_ agent: Agent) -> String {
        var parts: [String] = []
        // Pre-paid accounts (DeepSeek) report a balance; there are no usage windows to show.
        if let balance = agent.usage?.balance {
            let amounts = balance.walletAmounts
            parts.append(amounts.isEmpty ? "Balance not reported" : "Balance \(amounts.joined(separator: " · "))")
            if let updated = TimeFormat.date(balance.updatedAt ?? "") {
                parts.append("as of \(updated.formatted(date: .abbreviated, time: .shortened))")
            } else if let reason = balance.reason, !reason.isEmpty {
                parts.append(reason)
            }
            if let source = balance.source, !source.isEmpty { parts.append(source) }
            return parts.joined(separator: " · ")
        }
        if let fiveHour = agent.usage?.fiveHour { parts.append("5-hour \(Int(fiveHour))%") }
        if let weekly = agent.usage?.weekly { parts.append("Weekly \(Int(weekly))%") }
        if let reset = agent.usage?.resetAt, let date = TimeFormat.date(reset) {
            parts.append("weekly resets \(date.formatted(date: .abbreviated, time: .shortened))")
        }
        if parts.isEmpty { parts.append("Usage not reported") }
        if let source = agent.usage?.source, !source.isEmpty { parts.append(source) }
        return parts.joined(separator: " · ")
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
