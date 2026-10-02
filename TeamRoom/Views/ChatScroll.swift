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
    @ViewBuilder let content: () -> Content

    @State private var atBottom = true
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
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height + geometry.contentInsets.bottom
                    - geometry.contentOffset.y - geometry.containerSize.height < 80
            } action: { _, value in
                atBottom = value
                if userScrolling { following = value }
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
            .overlay(alignment: .bottomTrailing) {
                if !atBottom {
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
            .animation(.easeOut(duration: 0.15), value: atBottom)
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
