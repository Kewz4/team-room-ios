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
            #if DEBUG
            if model.isUITesting { ui = TestFixtures.image; return }
            #endif
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
                FullImageLoader(agentId: agentId, image: image, preview: ui)
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

/// Shows the thumbnail at once, then swaps in a sharper copy decoded for full screen.
struct FullImageLoader: View {
    @Environment(AppModel.self) private var model
    let agentId: String
    let image: EventImage
    let preview: UIImage
    @State private var full: UIImage?

    var body: some View {
        ImageViewer(image: full ?? preview, label: image.label)
            .task(id: image.id) {
                #if DEBUG
                if model.isUITesting { return }
                #endif
                full = await model.images.load(agentId: agentId, id: image.id, maxPixel: 2400)
            }
    }
}

struct ImageViewer: View {
    let image: UIImage
    let label: String?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var pinchStart: CGFloat?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                let factor = min(geometry.size.width / max(image.size.width, 1),
                                 geometry.size.height / max(image.size.height, 1))
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(image.size.width <= 128 ? .none : .high)
                        .frame(width: image.size.width * factor * scale,
                               height: image.size.height * factor * scale)
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                        .accessibilityIdentifier("zoom-image")
                        .onTapGesture(count: 2) { scale = scale > 1 ? 1 : 3 }
                }
                .defaultScrollAnchor(.center)
                .scrollIndicators(.hidden)
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { value in
                        if pinchStart == nil { pinchStart = scale }
                        scale = min(8, max(1, (pinchStart ?? 1) * value.magnification))
                    }
                    .onEnded { _ in pinchStart = nil })
            }
            .padding(.vertical, 60)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(.white)
            .glassEffect(.regular.interactive(), in: Circle())
            .padding(Tokens.Space.m)
            .accessibilityLabel("Close image")
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if let label, !label.isEmpty {
                    Text(label).font(TypeScale.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                }
                HStack(spacing: 12) {
                    Button { scale = max(1, scale / 1.5) } label: {
                        Image(systemName: "minus").frame(width: 44, height: 44)
                    }.accessibilityLabel("Zoom out").disabled(scale <= 1)
                    Text("\(Int((scale * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 48)
                        .accessibilityIdentifier("image-zoom-level")
                    Button { scale = min(8, scale * 1.5) } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                    }.accessibilityLabel("Zoom in").disabled(scale >= 8)
                    Button("Fit") { scale = 1; pinchStart = nil }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Fit image")
                }
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .glassEffect(.regular, in: Capsule())
            }
            .padding(Tokens.Space.m)
        }
        .statusBarHidden()
    }
}
