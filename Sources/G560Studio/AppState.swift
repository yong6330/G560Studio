import Foundation
import G560Core
import Observation
import AppKit

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
    var hasChanges: Bool {
        draft != applied || draftSchedule != store.schedule || draftScheduleEnabled != store.scheduleEnabled
            || draftAppRules != store.appRules || draftAppRulesEnabled != store.appRulesEnabled
    }
    private var iconTimer: Timer?
    private var scheduleTimer: Timer?
    private var lastFiring: Schedule.Firing?
    var draftSchedule: [ScheduleRule]
    var draftScheduleEnabled: Bool
    var draftAppRules: [AppRule]
    var draftAppRulesEnabled: Bool
    /// 앱 규칙이 발동 중이면 (규칙, 발동 전 활성 프로필 id)
    private var appOverride: (rule: AppRule, restoreID: UUID)?
    private var lastFrontApp: String?      // 자기 자신(설정 창) 제외한 마지막 앞 앱

    init() {
        engine = LightingEngine(device: device)
        let s = ProfileStore()
        store = s
        let p = s.active ?? Profile.makeDefault(name: "기본")
        applied = p
        draft = p
        draftSchedule = s.schedule
        draftScheduleEnabled = s.scheduleEnabled
        draftAppRules = s.appRules
        draftAppRulesEnabled = s.appRulesEnabled
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
        // 스케줄: 시작 시 1회 + 매분. 규칙이 바뀔 때만 발동 (수동 전환은 다음 규칙까지 유지).
        lastFiring = Schedule.activeFiring(store.schedule, at: Date())
        if store.scheduleEnabled, let f = lastFiring { fire(f.rule, force: true) }
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickSchedule() }
        }
        // 앱별 전환: 앞 앱이 바뀔 때마다
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.frontAppChanged(app?.bundleIdentifier) }
        }
        frontAppChanged(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    /// 앱 규칙: 일치하는 앱이 앞으로 오면 그 프로필, 벗어나면 발동 전 프로필로 복귀.
    func frontAppChanged(_ bundleID: String?) {
        if bundleID == Bundle.main.bundleIdentifier { return }   // 설정 창으로 오는 건 "앱을 벗어남"이 아님
        lastFrontApp = bundleID
        guard store.appRulesEnabled else { return }
        let match = bundleID.flatMap { b in store.appRules.first { $0.enabled && $0.bundleID == b } }
        if let m = match {
            if appOverride?.rule == m { return }                     // 같은 규칙, 같은 대상이면 그대로
            let restore = appOverride?.restoreID ?? store.activeID ?? store.profiles[0].id
            appOverride = (m, restore)
            if let p = store.profiles.first(where: { $0.id == m.profileID }) { apply(p, auto: true) }
        } else if let o = appOverride {
            appOverride = nil
            if let p = store.profiles.first(where: { $0.id == o.restoreID }) { apply(p, auto: true) }
        }
    }

    func tickSchedule() {
        let current = Schedule.activeFiring(store.schedule, at: Date())
        guard current != lastFiring else { return }
        lastFiring = current
        if store.scheduleEnabled, let f = current { fire(f.rule, force: false) }
    }

    private func fire(_ rule: ScheduleRule, force: Bool) {
        guard let p = store.profiles.first(where: { $0.id == rule.profileID }) else { return }
        if appOverride != nil { appOverride!.restoreID = p.id; return }   // 앱 규칙이 위 — 복귀 대상만 갱신
        if force || p.id != store.activeID { apply(p, auto: !force) }
    }

    /// 편집 중인 변경을 버리고 적용된 값으로 되돌림.
    func discardChanges() {
        draft = applied
        draftSchedule = store.schedule
        draftScheduleEnabled = store.scheduleEnabled
        draftAppRules = store.appRules
        draftAppRulesEnabled = store.appRulesEnabled
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

    /// 활성 프로필에 값 저장. 이름은 목록(store)의 것을 유지 — 이름 변경은 목록에서만 일어난다.
    private func persistActive(_ p: Profile) {
        if let i = store.profiles.firstIndex(where: { $0.id == store.activeID }) {
            var q = p; q.id = store.profiles[i].id; q.name = store.profiles[i].name
            store.profiles[i] = q
        }
        try? store.save()
    }

    /// 프로필 전체 적용 + 활성 프로필로 기록.
    /// `auto`: 스케줄/앱 규칙에 의한 전환 — 설정 창에서 편집 중인 초안은 건드리지 않는다.
    func apply(_ p: Profile, auto: Bool = false) {
        push(p, eq: p.eq != applied.eq)
        let editing = auto && draft != applied
        applied = p
        if !editing { draft = p }
        store.activeID = p.id
        try? store.save()
    }

    /// 설정 창 "동기화": draft를 장치에 반영하고 활성 프로필에 저장. 스케줄 초안도 저장·재평가.
    func sync() {
        if draft != applied {
            push(draft, eq: draft.eq != applied.eq)
            applied = draft
            persistActive(draft)
        }
        store.schedule = draftSchedule
        store.scheduleEnabled = draftScheduleEnabled
        store.appRules = draftAppRules
        store.appRulesEnabled = draftAppRulesEnabled
        try? store.save()
        if !store.appRulesEnabled, let o = appOverride {           // 앱 규칙을 끄면 발동 전 프로필로 복귀
            appOverride = nil
            if let p = store.profiles.first(where: { $0.id == o.restoreID }) { apply(p, auto: true) }
        }
        frontAppChanged(lastFrontApp ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier)   // 규칙 바꾸면 즉시 재평가
        // 현재 시각 기준 프로필로 즉시 전환, 이후 규칙 시각마다 다음 프로필로
        lastFiring = Schedule.activeFiring(store.schedule, at: Date())
        if store.scheduleEnabled, let f = lastFiring { fire(f.rule, force: true) }
    }

    /// 빠른 패널 슬라이더: 즉시 반영 (조명/EQ는 건드리지 않음).
    func quickSet(volume: Double? = nil, woofer: Int? = nil, eq: [Int]? = nil) {
        if let g = eq, connected {
            draft.eq = g; applied.eq = g
            do { try device.setEqualizer(g); deviceError = nil } catch { deviceError = "장치 명령 실패: \(error)" }
        }
        if let v = volume { draft.volume = v; applied.volume = v; try? OutputVolume.set(v) }
        if let w = woofer, connected {
            draft.woofer = w; applied.woofer = w
            do { try device.setWoofer(w); deviceError = nil } catch { deviceError = "장치 명령 실패: \(error)" }
        }
        persistActive(applied)
    }

    func deleteProfile(_ id: UUID) {
        guard store.profiles.count > 1 else { return }
        store.profiles.removeAll { $0.id == id }
        let fallback = store.profiles[0].id
        func retarget(_ r: ScheduleRule) -> ScheduleRule {   // 삭제된 프로필을 가리키는 규칙 정리
            var r = r
            if r.profileID == id { r.profileID = fallback }
            if r.fromProfileID == id { r.fromProfileID = fallback }
            return r
        }
        draftSchedule = draftSchedule.map(retarget)
        store.schedule = store.schedule.map(retarget)
        func retargetApp(_ r: AppRule) -> AppRule { var r = r; if r.profileID == id { r.profileID = fallback }; return r }
        draftAppRules = draftAppRules.map(retargetApp)
        store.appRules = store.appRules.map(retargetApp)
        if appOverride?.restoreID == id { appOverride?.restoreID = fallback }
        if store.activeID == id { apply(store.profiles[0]) } else { try? store.save() }
    }

    /// "공장 초기값" 프로필로 전환: 우퍼 40, EQ Flat, 사운드 반응 레인보우. 목록에 없으면 추가하고 활성화·저장.
    func restoreFactory() {
        var p = Profile.factory()
        if let existing = store.profiles.first(where: { $0.name == p.name }) { p.id = existing.id }
        if let i = store.profiles.firstIndex(where: { $0.id == p.id }) { store.profiles[i] = p } else { store.profiles.append(p) }
        push(p, eq: true)
        applied = p
        draft = p
        store.activeID = p.id
        try? store.save()
    }
}
