import SwiftUI

@main
struct NoirPokerApp: App {
    @State private var model = TableModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TableRootView(model: model)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.didEnterBackground()
            case .active: model.willEnterForeground()
            default: break
            }
        }
    }
}
