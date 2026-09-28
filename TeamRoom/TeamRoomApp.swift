import SwiftUI

@main
struct TeamRoomApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.boot() }
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
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Connecting to the team room…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .ready:
                RoomView()
            }
        }
    }
}
