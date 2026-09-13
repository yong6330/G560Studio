import Foundation
import G560Core
import Observation

@Observable @MainActor
final class AppState {
    let device = G560Device()
    let tap = AudioTap()
    let engine: LightingEngine
    var store = ProfileStore()
    var connected = false
    var audioError: String?
    var deviceError: String?
    var levels = AudioLevels.silence
    var zoneColors = ZoneColors.off
    var draft: Profile                       // 편집 중 값 (설정 창 바인딩)
    private var iconTimer: Timer?

    init() {
        engine = LightingEngine(device: device)
        let s = ProfileStore()
        store = s
        draft = s.active ?? Profile.makeDefault(name: "기본")
        device.onConnect = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.connected = true; self.deviceError = nil
                self.apply(self.draft)
            }
        }
        device.onDisconnect = { [weak self] in Task { @MainActor in self?.connected = false } }
        tap.onLevels = { [weak self] l in
            self?.engine.update(audio: l)
            Task { @MainActor in self?.levels = l }
        }
        device.start()
        do { try tap.start() } catch {
            audioError = "시스템 오디오 접근 실패(\(error)). 시스템 설정 → 개인정보 보호 → 화면 및 시스템 오디오 녹음에서 G560Studio를 허용하세요."
        }
        engine.start()
        iconTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.zoneColors = self?.engine.lastFrame ?? .off }
        }
    }

    /// 프로필 전체 적용: 조명 + 볼륨 + 우퍼 + EQ. activeID 저장.
    func apply(_ p: Profile) {
        draft = p
        engine.config = p.lighting
        engine.resend()
        try? OutputVolume.set(p.volume)
        store.activeID = p.id
        try? store.save()
        guard connected else { return }
        do { try device.setWoofer(p.woofer); try device.setEqualizer(p.eq); deviceError = nil }
        catch { deviceError = "장치 명령 실패: \(error)" }
    }

    /// 설정 창의 변경을 즉시 반영. EQ는 EEPROM이라 명시적으로만.
    func applyDraft(eq: Bool = false) {
        engine.config = draft.lighting
        try? OutputVolume.set(draft.volume)
        guard connected else { return }
        do {
            try device.setWoofer(draft.woofer)
            if eq { try device.setEqualizer(draft.eq) }
            deviceError = nil
        } catch { deviceError = "장치 명령 실패: \(error)" }
    }

    func saveDraftAsActive() {
        if let i = store.profiles.firstIndex(where: { $0.id == store.activeID }) { store.profiles[i] = draft }
        try? store.save()
    }

    /// 장치를 공장값(우퍼 40, EQ flat)으로, 조명은 끔. 프로필 파일은 건드리지 않음.
    func restoreFactory() {
        draft.woofer = G560.factoryWoofer
        draft.eq = G560.factoryEQ
        draft.lighting = .off
        applyDraft(eq: true)
    }
}
