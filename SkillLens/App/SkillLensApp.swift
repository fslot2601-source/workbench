import SwiftUI

@main
struct SkillLensApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
                .task { await model.bootstrap() }
        }
        .defaultSize(width: 1180, height: 760)

        Settings {
            DiagnosticsView()
                .environment(model)
                .frame(width: 620, height: 460)
        }
    }
}
