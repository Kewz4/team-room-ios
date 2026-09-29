import SwiftUI
import PDFKit

extension AppModel {
    func linkAction(relativeTo: String? = nil) -> OpenURLAction {
        OpenURLAction { url in
            switch LinkRouting.resolve(url, relativeTo: relativeTo, server: self.baseURLString) {
            case .artifact(let path): self.artifact = ArtifactRequest(path: path); return .handled
            case .web(let url): return .systemAction(url)
            case .unsupported:
                self.actionError = "This link type cannot be opened. Shared project reports and web links are supported."
                return .discarded
            }
        }
    }
}

struct ArtifactPreview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ArtifactRequest
    @State private var data: Data?
    @State private var error: String?

    private var name: String { request.path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? "Report" }
    private var ext: String { (name as NSString).pathExtension.lowercased() }

    var body: some View {
        NavigationStack {
            Group {
                if let data {
                    if ["png", "jpg", "jpeg", "webp", "gif"].contains(ext), let image = UIImage(data: data) {
                        ImageViewer(image: image, label: name)
                    } else if ext == "pdf", let document = PDFDocument(data: data) {
                        PDFPreview(document: document)
                    } else if let text = String(data: data, encoding: .utf8) {
                        ScrollView {
                            if ext == "md" { MarkdownText(text: text).padding() }
                            else { CodeText(text: text, collapsible: true).padding() }
                        }
                        .environment(\.openURL, model.linkAction(relativeTo: request.path))
                    } else { ContentUnavailableView("Preview unavailable", systemImage: "doc", description: Text("This file is not a supported text report or image.")) }
                } else if let error {
                    ContentUnavailableView {
                        Label("Could not open file", systemImage: "doc.badge.ellipsis")
                    } description: { Text(error) } actions: { Button("Try again") { Task { await load() } } }
                } else { ProgressView("Opening report…") }
            }
            .background(Tokens.background)
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task(id: request.path) { await load() }
    }

    private func load() async {
        data = nil; error = nil
        #if DEBUG
        if model.isUITesting { data = "# Fixture report preview\n\nThe report link opened successfully.\n\n| Check | Result |\n| --- | --- |\n| Preview | Passed |".data(using: .utf8); return }
        #endif
        do { data = try await model.client.artifact(path: request.path) }
        catch { self.error = error.localizedDescription }
    }
}

private struct PDFPreview: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.document = document; return view }
    func updateUIView(_ view: PDFView, context: Context) { if view.document !== document { view.document = document } }
}
