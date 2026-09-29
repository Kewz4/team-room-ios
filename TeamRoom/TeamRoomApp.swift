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
                    Text("Connecting to the team room…")
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tokens.background)
            case .ready:
                RoomView()
            }
        }
    }
}
