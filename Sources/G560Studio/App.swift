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
        Settings { SettingsView().environment(state) }
    }
}
