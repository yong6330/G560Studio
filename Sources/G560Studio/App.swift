import SwiftUI
import G560Core

/// 메뉴바 아이콘·빠른 패널·설정 창을 AppKit으로 직접 관리.
/// SwiftUI MenuBarExtra는 아이콘을 20Hz로 갱신할 때마다 전체 레이아웃을 다시 해서 CPU를 많이 먹는다(실측 ~25%).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    let state = AppState()
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var iconTimer: Timer?
    private var lastIconKey: (AudioLevels, ZoneColors, Bool)?
    private var styleWas: MenuBarStyle = .wave

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.imagePosition = .imageOnly
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: QuickPanel().environment(state))
        updateIcon()
        // 아이콘: 12Hz, 눈에 띄게 바뀔 때만 다시 그림. 모니터가 여러 대면 AppKit이 메뉴바마다 복제본을 다시 그려서
        // 갱신 한 번이 비싸다(실측: 20Hz 무조건 갱신 시 메인 스레드 ~18%).
        iconTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateIcon() }
        }
    }

    /// SwiftUI App/Settings 씬이 없어 기본 메뉴도 없다 — 설정 창 텍스트 필드의 ⌘C/⌘V/⌘A/⌘Z가 동작하도록 편집 메뉴만 만든다.
    private func installMainMenu() {
        let main = NSMenu(), edit = NSMenu(title: "편집")
        for (title, action, key) in [("실행 취소", "undo:", "z"), ("오려두기", "cut:", "x"), ("복사", "copy:", "c"), ("붙여넣기", "paste:", "v"), ("전체 선택", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        for sub in [NSMenu(), edit] { let i = NSMenuItem(); i.submenu = sub; main.addItem(i) }   // 첫 칸은 앱 메뉴 자리
        NSApp.mainMenu = main
    }

    private func updateIcon() {
        let key = (state.levels, state.zoneColors, state.connected)
        if styleWas != state.menuBarStyle { styleWas = state.menuBarStyle; lastIconKey = nil }
        if let k = lastIconKey, k.2 == key.2 {
            let rmsDelta = abs(k.0.rms - key.0.rms)
            let colorDelta = zip(k.1.zones, key.1.zones).map { a, b in max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b))) }.max() ?? 0
            let silent = key.0.rms < 0.002 && k.0.rms < 0.002
            if silent && colorDelta < 6 { return }                    // 무음 + 색 거의 그대로 → 갱신 없음
            if rmsDelta < 0.01 && colorDelta < 6 { return }           // 미세 변화는 건너뜀
        }
        lastIconKey = key
        statusItem.button?.image = MenuBarIcon.render(levels: key.0, zones: key.1, connected: key.2, style: state.menuBarStyle)
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePanel() { popover.performClose(nil) }

    func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "G560Studio 설정"
            w.contentMinSize = NSSize(width: 440, height: 520)
            w.contentViewController = NSHostingController(rootView: SettingsView().environment(state))
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        closePanel()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
