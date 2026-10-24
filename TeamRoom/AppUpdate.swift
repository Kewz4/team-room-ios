import SwiftUI
import UIKit

/// GET /api/app-update: the newest build the PC offers. Whatever way the app was installed (a signed link, a file),
/// the number is what counts: a build above the installed one means an update is ready.
struct AppUpdateInfo: Decodable, Hashable {
    var build: Int
    var version: String
    var notes: String?
    var installUrl: String?

    private enum CodingKeys: String, CodingKey { case build, version, notes, installUrl }

    /// Bad JSON, a missing build or a negative one throws, and the caller shows nothing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let number = c.lenientNumber(.build), number >= 0, number < 1_000_000_000 else {
            throw DecodingError.dataCorruptedError(forKey: .build, in: c, debugDescription: "No usable build number.")
        }
        build = Int(number)
        let name = c.lenientString(.version)?.trimmingCharacters(in: .whitespaces) ?? ""
        version = name.isEmpty ? "build \(build)" : name
        let note = c.lenientString(.notes)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        notes = note.isEmpty ? nil : note
        installUrl = c.lenientString(.installUrl)
    }

    init(build: Int, version: String, notes: String? = nil, installUrl: String? = nil) {
        self.build = build
        self.version = version
        self.notes = notes
        self.installUrl = installUrl
    }

    /// Only an itms-services install link or an https link is opened; anything else is treated as no link.
    var installLink: URL? {
        guard let text = installUrl?.trimmingCharacters(in: .whitespaces), !text.isEmpty,
              let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "itms-services" || scheme == "https" else { return nil }
        return url
    }
}

enum InstalledApp {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    static var buildText: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }
    static var build: Int { Int(buildText) ?? 0 }
    static var label: String { "\(version) (\(buildText))" }
}

/// "Team Room 1.3.1 is ready" with an Install button; only the text when the PC offers no link.
struct UpdateBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let update = model.update {
            HStack(spacing: Tokens.Space.s) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Tokens.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Team Room \(update.version) is ready")
                        .font(TypeScale.captionMedium)
                        .foregroundStyle(Tokens.textPrimary)
                    if let notes = update.notes {
                        Text(notes)
                            .font(.caption2)
                            .foregroundStyle(Tokens.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if let link = update.installLink {
                    Button("Install") { UIApplication.shared.open(link) }
                        .font(TypeScale.captionMedium)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityIdentifier("update-install")
                }
            }
            .padding(.horizontal, Tokens.Space.m)
            .padding(.vertical, 8)
            .background(Tokens.accentSoft)
            .overlay(alignment: .bottom) { Rectangle().fill(Tokens.hairline).frame(height: 0.5) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("update-banner")
        }
    }
}

/// Settings: what is installed, when the PC was last asked, and the update if there is one.
struct AppUpdateSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            LabeledContent("Installed", value: "Version \(InstalledApp.version) · build \(InstalledApp.buildText)")
            LabeledContent("Last checked", value: model.updateCheckedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not yet")
            if let update = model.update {
                LabeledContent("Update", value: "\(update.version) (build \(update.build)) is ready")
                if let link = update.installLink {
                    Button("Install \(update.version)") { UIApplication.shared.open(link) }
                }
            } else if model.updateCheckedAt != nil {
                LabeledContent("Update", value: "Up to date")
            }
            Button("Check for updates") { Task { await model.checkForUpdate() } }
        } header: {
            Text("App")
        } footer: {
            Text("Team Room asks your PC for a newer build when it opens and when you come back to it.")
        }
        .accessibilityIdentifier("app-update-section")
    }
}
