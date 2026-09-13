import SwiftUI

@main
struct G560StudioApp: App {
    var body: some Scene {
        MenuBarExtra("G560", systemImage: "hifispeaker") {
            Text("G560Studio").padding()
        }.menuBarExtraStyle(.window)
    }
}
