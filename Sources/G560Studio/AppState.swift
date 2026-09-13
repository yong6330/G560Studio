import Foundation
import G560Core
import Observation

@Observable @MainActor
final class AppState {
    let device = G560Device()
    let tap = AudioTap()
    let engine: LightingEngine
    var store: ProfileStore
    var connected = false
    var audioError: String?
    var deviceError: String?
    var levels = AudioLevels.silence
    var zoneColors = ZoneColors.off        // 엔진이 마지막으로 보낸 프레임 (30Hz)
    var applied: Profile                   // 장치에 반영된 값
    var draft: Profile                     // 설정 창에서 편집 중인 값
    var hasChanges: Bool { draft != applied }
    private var iconTimer: Timer?

    init() {
        engine = LightingEngine(device: device)
        let s = ProfileStore()
        store = s
        let p = s.active ?? Profile.makeDefault(name: "기본")
        applied = p
        draft = p
        device.onConnect = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.connected = true; self.deviceError = nil
                self.push(self.applied, eq: true)
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

    /// 장치/시스템에 실제로 쓴다. EQ는 EEPROM이라 바뀐 경우에만.
    private func push(_ p: Profile, eq: Bool) {
        engine.config = p.lighting
        engine.resend()
        try? OutputVolume.set(p.volume)
        guard connected else { return }
        do {
            try device.setWoofer(p.woofer)
            if eq { try device.setEqualizer(p.eq) }
            deviceError = nil
        } catch { deviceError = "장치 명령 실패: \(error)" }
    }

    /// 프로필 전체 적용 + 활성 프로필로 기록.
    func apply(_ p: Profile) {
        push(p, eq: p.eq != applied.eq)
        applied = p
        draft = p
        store.activeID = p.id
        try? store.save()
    }

    /// 설정 창 "동기화": draft를 장치에 반영하고 활성 프로필에 저장.
    func sync() {
        push(draft, eq: draft.eq != applied.eq)
        applied = draft
        if let i = store.profiles.firstIndex(where: { $0.id == store.activeID }) { store.profiles[i] = draft }
        try? store.save()
    }

    /// 빠른 패널 슬라이더: 즉시 반영 (조명/EQ는 건드리지 않음).
    func quickSet(volume: Double? = nil, woofer: Int? = nil) {
        if let v = volume { draft.volume = v; applied.volume = v; try? OutputVolume.set(v) }
        if let w = woofer, connected {
            draft.woofer = w; applied.woofer = w
            do { try device.setWoofer(w); deviceError = nil } catch { deviceError = "장치 명령 실패: \(error)" }
        }
        if let i = store.profiles.firstIndex(where: { $0.id == store.activeID }) { store.profiles[i] = applied }
        try? store.save()
    }

    /// 장치를 공장값(우퍼 40, EQ flat)으로, 조명은 끔. 프로필 파일은 건드리지 않음.
    func restoreFactory() {
        draft.woofer = G560.factoryWoofer
        draft.eq = G560.factoryEQ
        draft.lighting = .off
        push(draft, eq: true)
        applied = draft
    }
}
