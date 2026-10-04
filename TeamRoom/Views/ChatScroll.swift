import SwiftUI
import UIKit

/// Chat scrolling shared by the team chat and the agent rooms.
///
/// Rows are lazy (only what is on screen is laid out; the old conversation view laid out every message on every
/// update). It starts at the newest message, keeps following new text while you are at the bottom, stops following
/// as soon as you scroll up to read, and shows a jump-to-latest button until you return.
struct ChatScroll<Content: View>: View {
    /// Changes whenever content grows (new message, longer streamed text).
    let followKey: Int
    /// Scrolls to this row id when set (deep links, notification taps).
    @Binding var focus: String?
    /// 1.2: off for an empty chat, whose suggestions can reach under the keyboard but hold no newer message to jump to.
    var jumpEnabled = true
    @ViewBuilder let content: () -> Content

    @State private var atBottom = true
    @State private var showJump = false
    @State private var following = true
    @State private var userScrolling = false
    @State private var handle = ScrollHandle()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content()
                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                        .accessibilityIdentifier("conversation-bottom")
                }
                .padding(.horizontal, Tokens.Space.m)
                .padding(.top, Tokens.Space.s)
                .padding(.bottom, Tokens.Space.m)
                .background(ScrollHandleBinder(handle: handle) {
                    if following { handle.bottom() }
                })
            }
            .accessibilityIdentifier("conversation-scroll")
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.hard, for: .top)
            .onScrollGeometryChange(for: [CGFloat].self) { geometry in
                // Any change of position, size or insets. The distance itself comes from UIKit (ScrollHandle): mixing
                // SwiftUI's geometry conventions showed the jump button at the bottom and in an empty chat.
                [geometry.contentOffset.y, geometry.contentSize.height, geometry.containerSize.height,
                 geometry.contentInsets.top, geometry.contentInsets.bottom]
            } action: { _, _ in
                // Short content (nothing to scroll) and a not-yet-attached view count as at the bottom.
                let value = (handle.distanceFromBottom ?? 0) < 80
                if value != atBottom { atBottom = value }
                if userScrolling && following != value { following = value }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height
            } action: { old, new in
                // Lazy rows measure themselves after the first layout and answers grow while streaming:
                // keep the newest line in view while following.
                guard new > old, following, !userScrolling else { return }
                handle.bottom()
            }
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting || phase == .decelerating {
                    userScrolling = true
                } else if phase == .idle && userScrolling {
                    following = atBottom
                    userScrolling = false
                }
            }
            .onChange(of: followKey) { _, _ in
                guard following, !userScrolling else { return }
                Task { @MainActor in
                    await Task.yield()
                    if following && !userScrolling { handle.bottom() }
                }
            }
            .onChange(of: focus) { _, id in
                guard let id else { return }
                following = false
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                focus = nil
            }
            .task(id: atBottom) {
                // Appear only when away from the end for a moment, so a growing answer that is being followed
                // never flickers the button; disappear at once on return.
                guard !atBottom else { showJump = false; return }
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled && !atBottom { showJump = true }
            }
            .overlay(alignment: .bottomTrailing) {
                if showJump && jumpEnabled {
                    Button(action: jumpToLatest) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.glass)
                    .clipShape(Circle())
                    .padding(.trailing, Tokens.Space.m)
                    .padding(.bottom, Tokens.Space.s)
                    .accessibilityLabel("Scroll to latest")
                    .accessibilityIdentifier("jump-latest")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.15), value: showJump)
        }
    }

    private func jumpToLatest() {
        following = true
        userScrolling = false
        handle.bottom()
        Task { @MainActor in
            await Task.yield()
            if following && !userScrolling { handle.bottom() }
        }
    }
}

/// Long-press actions shared by every message: copy, select text (full-screen sheet) and share.
struct MessageActions: ViewModifier {
    let text: String
    let title: String
    @State private var selecting = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    UIPasteboard.general.string = text
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button {
                    selecting = true
                } label: { Label("Select Text", systemImage: "selection.pin.in.out") }
                ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            .sheet(isPresented: $selecting) {
                SelectTextSheet(title: title, text: text)
            }
    }
}

extension View {
    func messageActions(text: String, title: String) -> some View {
        modifier(MessageActions(text: text, title: title))
    }
}
