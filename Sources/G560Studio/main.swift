import AppKit

// SwiftUI App/@main 없이 순수 AppKit 진입점: Settings 씬이 없으니 macOS 신버전이 빈 "Settings" 창을 띄우지 않는다.
MainActor.assumeIsolated {
    let app = NSApplication.shared          // AppDelegate(AppState) 생성 전에 NSApplication부터
    let delegate = AppDelegate()
    app.delegate = delegate                 // delegate는 weak — run()이 끝나지 않으니 이 스코프가 붙들고 있다
    app.run()
}
