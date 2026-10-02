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
                Section {
                    NavigationLink {
                        BarkSetupView()
                    } label: {
                        HStack {
                            Label("Background notifications", systemImage: "bell.badge")
                            Spacer()
                            Text(barkSummary)
                                .font(TypeScale.caption)
                                .foregroundStyle(model.bark?.configured == true ? Tokens.idle : Tokens.textTertiary)
                        }
                    }
                    .accessibilityIdentifier("bark-setup")
                    Toggle("Alerts while the app is open", isOn: Binding(
                        get: { model.notifications.enabled },
                        set: { value in
                            if value { Task { await model.notifications.enable() } } else { model.notifications.disable() }
                        }))
                    if model.notifications.enabled {
                        Button("Send a test alert") { Task { await model.notifications.sendTest() } }
                    }
                    if let error = model.notifications.permissionError {
                        Text(error).font(TypeScale.caption).foregroundStyle(Tokens.failure)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Background notifications reach you when Team Room is closed, through the Bark app with end-to-end encryption. While the app is open it shows alerts itself.")
                }

                Section("Connection") {
                    LabeledContent("Address", value: hostLabel)
                    LabeledContent("Live updates", value: socketLabel)
                    if let lastSync = model.team.lastSync {
                        LabeledContent("Last update", value: lastSync.formatted(date: .omitted, time: .standard))
                    }
                    if let relay = model.team.relay {
                        LabeledContent("Team relay", value: relay.enabled == false ? "Paused" : relay.paused == true ? "Holding for maintenance" : "Running · \(relay.waiting ?? 0) waiting")
                    }
                    Button("Refresh now") { model.refresh() }
                    Button("Recheck runners") { Task { await model.checkRunners() } }
                }

                Section("Teammates") {
                    ForEach(model.team.agents) { agent in
                        HStack(spacing: 10) {
                            AgentAvatar(worker: AgentStyle.worker(for: agent), size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.displayName).font(.subheadline.weight(.semibold))
                                Text([agent.account, agent.modelLabel].compactMap { $0 }.joined(separator: " · "))
                                    .font(TypeScale.caption)
                                    .foregroundStyle(Tokens.textSecondary)
                                Text(usageLine(agent)).font(.caption2).foregroundStyle(Tokens.textTertiary)
                            }
                        }
                    }
                }

                Section {
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
                            Text(link).font(.caption.monospaced()).textSelection(.enabled).lineLimit(3)
                            HStack {
                                Button(copied ? "Copied" : "Copy link") {
                                    UIPasteboard.general.string = link
                                    copied = true
                                }
                                ShareLink(item: link) { Label("Share", systemImage: "square.and.arrow.up") }
                            }
                            .font(.caption)
                        }
                    }
                } header: {
                    Text("Devices")
                } footer: {
                    Text("A device link pairs another phone or browser. It works once, for 30 minutes. Signed-in devices stay signed in while they are used at least once a month.")
                }

                Section {
                    Button("Sign out this device", role: .destructive) {
                        model.signOut()
                        dismiss()
                    }
                } footer: {
                    Text("Team Room \(appVersion) — private client for your PC's Team Room bridge.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await model.refreshBark() }
        }
    }

    private var barkSummary: String {
        guard let bark = model.bark else { return "Not set up" }
        if !bark.configured { return "Not set up" }
        if bark.lastResult?.ok == false { return "Check setup" }
        return bark.verifiedAt != nil ? "On" : "Not tested"
    }

    private var hostLabel: String {
        URL(string: model.baseURLString)?.host.map { host in
            host.hasSuffix(".ts.net") ? "Permanent (Tailscale)" : host.hasSuffix(".trycloudflare.com") ? "Temporary tunnel" : host
        } ?? "Not set"
    }

    private var socketLabel: String {
        switch model.socketStatus {
        case .live: return "Live"
        case .connecting: return "Connecting"
        case .reconnecting: return "Reconnecting"
        case .offline: return "Offline"
        }
    }

    private func usageLine(_ agent: Agent) -> String {
        var parts: [String] = []
        if let balance = agent.usage?.balance {
            let amounts = balance.walletAmounts
            parts.append(amounts.isEmpty ? "Balance not reported" : "Balance \(amounts.joined(separator: " · "))")
            if let source = balance.source, !source.isEmpty { parts.append(source) }
            return parts.joined(separator: " · ")
        }
        if let fiveHour = agent.usage?.fiveHour { parts.append("5-hour \(Int(fiveHour))%") }
        if let weekly = agent.usage?.weekly { parts.append("weekly \(Int(weekly))%") }
        if let monthly = agent.usage?.monthly { parts.append("monthly \(Int(monthly))%") }
        if let reason = agent.limit?.reason, !reason.isEmpty, agent.limit?.level != "ok" { parts.append(reason) }
        if let reset = agent.usage?.resetAt, let date = TimeFormat.date(reset) {
            parts.append("resets \(date.formatted(date: .abbreviated, time: .shortened))")
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

/// Guided Bark setup: install Bark, paste its key, turn on encryption with the key shown here, send a test.
struct BarkSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var input = ""
    @State private var settings: BarkSettings?
    @State private var busy = false
    @State private var message: String?
    @State private var failed = false
    @State private var copiedKey = false

    var body: some View {
        Form {
            Section {
                statusRow
            }

            Section {
                Button {
                    if let url = URL(string: model.bark?.appStore ?? "https://apps.apple.com/app/id1403753865") { openURL(url) }
                } label: {
                    Label("Get Bark from the App Store", systemImage: "arrow.down.app")
                }
            } header: {
                Text("1 · Install Bark")
            } footer: {
                Text("Bark is a free, open-source app that receives custom notifications. Open it once and allow notifications.")
            }

            Section {
                TextField("https://api.day.app/your-key/…", text: $input, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(TypeScale.mono)
                    .accessibilityIdentifier("bark-key")
                HStack {
                    PasteButton(payloadType: String.self) { strings in
                        if let text = strings.first { input = text }
                    }
                    .labelStyle(.titleAndIcon)
                    Spacer()
                    Button {
                        Task { await connect() }
                    } label: {
                        if busy { ProgressView() } else { Text(model.bark?.configured == true ? "Update" : "Connect") }
                    }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                }
            } header: {
                Text("2 · Paste your Bark key")
            } footer: {
                Text("In Bark, copy the server address shown on its main screen (it contains your key) and paste it here. It is stored only on your PC.")
            }

            Section {
                if let settings {
                    LabeledContent("Algorithm", value: settings.algorithm)
                    LabeledContent("Mode", value: settings.mode)
                    LabeledContent("Padding", value: settings.padding ?? "noPadding")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Key").font(TypeScale.caption).foregroundStyle(Tokens.textSecondary)
                        Text(settings.key).font(TypeScale.mono).textSelection(.enabled)
                        Button(copiedKey ? "Copied" : "Copy key") {
                            UIPasteboard.general.string = settings.key
                            copiedKey = true
                        }
                        .font(TypeScale.captionMedium)
                    }
                    if let iv = settings.iv {
                        LabeledContent("IV (if Bark asks)", value: iv).font(TypeScale.mono)
                    }
                    Button {
                        // Custom schemes go straight to the system; the in-app link router only handles web and reports.
                        if let url = URL(string: "bark://") { UIApplication.shared.open(url) }
                    } label: { Label("Open Bark", systemImage: "arrow.up.forward.app") }
                } else {
                    Button("Show encryption settings") { Task { await loadSettings() } }
                        .disabled(model.bark?.configured != true)
                }
            } header: {
                Text("3 · Turn on encryption in Bark")
            } footer: {
                Text("In Bark: Push Encryption → choose AES256, mode GCM, paste the key, Done. Every notification is then end-to-end encrypted: neither Bark's server nor Apple can read it.")
            }

            Section {
                Button {
                    Task { await test() }
                } label: {
                    Label("Send a test notification", systemImage: "paperplane")
                }
                .disabled(model.bark?.configured != true || busy)
                if let message {
                    Text(message)
                        .font(TypeScale.caption)
                        .foregroundStyle(failed ? Tokens.failure : Tokens.idle)
                }
            } header: {
                Text("4 · Test")
            } footer: {
                Text("If the notification says “Decryption Failed”, the key in Bark does not match: copy it again. Tapping a Team Room notification opens the right screen here.")
            }

            if let events = model.bark?.events {
                Section("Notify me about") {
                    eventToggle("A teammate needs my input", key: \.needs_input, value: events.needs_input ?? true)
                    eventToggle("Coordinator answers in the team chat", key: \.room, value: events.room ?? true)
                    eventToggle("Failed or interrupted work", key: \.failed, value: events.failed ?? true)
                    eventToggle("Tasks I sent are finished", key: \.mine, value: events.mine ?? true)
                    eventToggle("Every finished task (very frequent)", key: \.completed, value: events.completed ?? false)
                }
            }

            if model.bark?.configured == true {
                Section {
                    Button("Turn off background notifications", role: .destructive) {
                        Task {
                            model.bark = try? await model.client.barkRemove()
                            settings = nil
                        }
                    }
                }
            }
        }
        .navigationTitle("Background notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refreshBark() }
    }

    @ViewBuilder private var statusRow: some View {
        if let bark = model.bark, bark.configured {
            VStack(alignment: .leading, spacing: 4) {
                Label(bark.verifiedAt != nil ? "Working" : "Connected — send a test", systemImage: bark.verifiedAt != nil ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(bark.verifiedAt != nil ? Tokens.idle : Tokens.working)
                Text("Device \(bark.deviceHint ?? "") · \(bark.server ?? "api.day.app")")
                    .font(TypeScale.caption)
                    .foregroundStyle(Tokens.textSecondary)
                if let last = bark.lastResult, last.ok == false, let error = last.error {
                    Text("Last notification failed: \(error)").font(TypeScale.caption).foregroundStyle(Tokens.failure)
                }
            }
        } else {
            Label("Not set up yet", systemImage: "bell.slash").foregroundStyle(Tokens.textSecondary)
        }
    }

    private func eventToggle(_ title: String, key: WritableKeyPath<BarkEvents, Bool?>, value: Bool) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: { newValue in
            Task {
                var events = BarkEvents()
                events[keyPath: key] = newValue
                if let status = try? await model.client.barkEvents(events) { model.bark = status }
            }
        }))
    }

    private func connect() async {
        busy = true
        defer { busy = false }
        do {
            let response = try await model.client.barkSetup(deviceKey: input, server: nil)
            model.bark = response.status
            settings = response.settings
            message = "Connected. Now turn on encryption in Bark with the key below, then send a test."
            failed = false
        } catch {
            message = (error as? ClientError)?.message ?? error.localizedDescription
            failed = true
        }
    }

    private func loadSettings() async {
        settings = try? await model.client.barkSettings()
    }

    private func test() async {
        busy = true
        defer { busy = false }
        do {
            let result = try await model.client.barkTest()
            if let status = result.status { model.bark = status }
            failed = result.ok != true
            message = result.ok == true ? "Sent. You should see “Team Room” in a moment." : "Bark did not accept the test: \(result.error ?? "unknown error")"
        } catch {
            failed = true
            message = (error as? ClientError)?.message ?? error.localizedDescription
        }
    }
}
