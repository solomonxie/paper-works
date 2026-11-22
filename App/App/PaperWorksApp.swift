import SwiftUI

@main
struct PaperWorksApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    init() { Notifications.shared.install() }

    var body: some Scene {
        WindowGroup {
            Group {
                if model.ready { rootView } else { Color.clear }
            }
            .environment(model)
            .task { await model.start() }
            .onChange(of: phase) { _, new in 
                if new == .active { model.becameActive() }
                if new == .background { model.wentToBackground() }
            }
        }
    }

    @ViewBuilder private var rootView: some View {
        RootView()
    }
}
