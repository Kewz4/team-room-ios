import SwiftUI

@main
struct TeamRoomApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Tokens.accent)
                .task { pushDelegate.notifications = model.notifications; await model.boot() }
                .onChange(of: scenePhase) { _, phase in
                    model.sceneChanged(phase == .active)
                }
                .onOpenURL { url in
                    model.router.open(url)
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .pairing:
                PairView()
            case .connecting:
                VStack(spacing: Tokens.Space.m) {
                    ProgressView()
                    Text("Connecting to your PC…")
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tokens.background)
            case .ready:
                MainTabView()
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.phase)
        #if DEBUG
        .modifier(UITestAppearance())
        #endif
        .onChange(of: model.router.pendingPairLink) { _, link in
            guard let link, model.phase == .pairing else { return }
            model.router.pendingPairLink = nil
            Task { await model.pair(link) }
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var router = model.router
        TabView(selection: $router.tab) {
            Tab("Team", systemImage: "bubble.left.and.text.bubble.right", value: Router.Tab.team) {
                TeamChatView()
            }
            .badge(model.unreadRoomCount)

            Tab("Agents", systemImage: "person.3", value: Router.Tab.agents) {
                AgentsListView()
            }
            .badge(model.team.needsInput.count)

            Tab("Board", systemImage: "chart.bar.doc.horizontal", value: Router.Tab.board) {
                BoardView()
            }

            Tab("Notes", systemImage: "note.text", value: Router.Tab.notes) {
                NotesView()
            }

            Tab("Inbox", systemImage: "tray", value: Router.Tab.inbox) {
                InboxView()
            }
            .badge(model.notifications.unreadCount)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(\.openURL, model.linkAction())
        .sheet(item: Binding(get: { model.artifact }, set: { model.artifact = $0 })) { request in
            ArtifactPreview(request: request)
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { model.actionError = nil }
        } message: {
            Text(model.actionError ?? "")
        }
    }
}

/// Gear button that opens Settings, shared by every tab's navigation bar.
struct SettingsToolbarItem: ToolbarContent {
    let router: Router

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                router.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings-button")
        }
    }
}

#if DEBUG
/// UI-test launch options: -ui-dark forces dark mode, -ui-large-type an accessibility text size.
struct UITestAppearance: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-large-type") {
            content
                .preferredColorScheme(arguments.contains("-ui-dark") ? .dark : nil)
                .dynamicTypeSize(.accessibility2)
        } else {
            content.preferredColorScheme(arguments.contains("-ui-dark") ? .dark : nil)
        }
    }
}
#endif
