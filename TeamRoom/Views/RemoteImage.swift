import SwiftUI
import UIKit

struct RemoteImage: View {
    @Environment(AppModel.self) private var model
    let agentId: String
    let image: EventImage
    var side: CGFloat = 84

    @State private var ui: UIImage?
    @State private var failed = false
    @State private var showViewer = false

    var body: some View {
        Button {
            if ui != nil { showViewer = true }
        } label: {
            ZStack {
                if let ui {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.s, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.s, style: .continuous)
                    .stroke(Tokens.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(image.label ?? "Image attachment")
        .task(id: image.id) {
            guard image.status == "available", ui == nil, !failed else { return }
            let loaded = await model.images.load(agentId: agentId, id: image.id)
            if let loaded {
                ui = loaded
            } else {
                failed = true
            }
        }
        .fullScreenCover(isPresented: $showViewer) {
            if let ui {
                ImageViewer(image: ui, label: image.label)
            }
        }
    }

    @ViewBuilder private var placeholder: some View {
        if image.status != "available" || failed {
            VStack(spacing: Tokens.Space.xs) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 16))
                Text("Unavailable")
                    .font(.system(size: 9))
            }
            .foregroundStyle(Tokens.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.surfaceAlt)
        } else {
            ZStack {
                Tokens.surfaceAlt
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

struct ImageViewer: View {
    let image: UIImage
    let label: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(Tokens.Space.s)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.35))
                    .padding(Tokens.Space.m)
            }
            .accessibilityLabel("Close")
        }
        .overlay(alignment: .bottom) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(TypeScale.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(Tokens.Space.m)
            }
        }
        .statusBarHidden()
    }
}
