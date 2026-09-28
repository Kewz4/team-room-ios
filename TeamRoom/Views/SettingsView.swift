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
                                Text(agent.state ?? "unknown")
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
        if let weekly = agent.usage?.weekly { parts.append("Weekly \(Int(weekly))% used") }
        if let fiveHour = agent.usage?.fiveHour { parts.append("Five-hour \(Int(fiveHour))%") }
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
