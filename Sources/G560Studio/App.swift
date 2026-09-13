import SwiftUI
import G560Core

@main
struct G560StudioApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            QuickPanel().environment(state)
        } label: {
            Image(nsImage: MenuBarIcon.render(levels: state.levels, zones: state.zoneColors, connected: state.connected))
        }
        .menuBarExtraStyle(.window)

        // Settings 씬 대신 일반 Window: LSUIElement 앱에서 확실히 앞으로 가져오기 위해
        Window("G560Studio 설정", id: "settings") {
            SettingsView().environment(state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
