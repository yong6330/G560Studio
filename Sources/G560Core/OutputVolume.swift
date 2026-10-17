import CoreAudio

/// G560 오디오 장치의 CoreAudio 출력 볼륨. HID++ 아님 (protocol.md).
public enum OutputVolume {
    public enum VolumeError: Error { case noDevice, setFailed }

    /// 쓰기 하한. 2026-09-13 G560이 "볼륨 0 + 뮤트"에서 펌웨어가 래치된 것으로 의심돼(원인 미확정) 0으로는 절대 내리지 않는다.
    /// ponytail: 0.05는 실측 근거 없는 추정치. 원인이 확정되면 조정. 뮤트 속성은 아예 건드리지 않는다.
    public static let minVolume = 0.05
    static let epsilon = 0.005   // 이 미만 차이는 쓰지 않음 (슬라이더 떨림·프로필 재적용 중복 방지)

    public static func safe(_ v: Double) -> Double { v.isNaN ? minVolume : min(1, max(minVolume, v)) }
    static func shouldWrite(current: Double?, target: Double) -> Bool { current.map { abs($0 - target) >= epsilon } ?? true }

    static func allDevices() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids
    }

    static func name(_ id: AudioObjectID) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        // 이 속성은 +1 retain된 CFString을 돌려준다 — Unmanaged로 받아야 메모리 안전하고 새지 않는다.
        var s: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &s) == noErr, let s else { return "" }
        return s.takeRetainedValue() as String
    }

    public static func g560DeviceID() -> AudioObjectID? { allDevices().first { name($0).contains("G560") } }

    static func volAddr(_ ch: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                   mScope: kAudioDevicePropertyScopeOutput, mElement: ch)
    }

    public static func get() -> Double? {
        guard let id = g560DeviceID() else { return nil }
        for ch: UInt32 in [0, 1] {   // main, 없으면 L
            var a = volAddr(ch)
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(id, &a), AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr {
                return Double(v)
            }
        }
        return nil
    }

    /// 모든 호출자가 지나는 단일 쓰기 지점: 하한 적용 + 현재 값과 같으면 생략.
    /// ponytail: 속도 제한은 없음 — 호출자가 슬라이더 놓을 때·프로필 적용 때만 부른다. 드래그 중 호출이 생기면 여기서 합칠 것.
    public static func set(_ value: Double) throws {
        guard let id = g560DeviceID() else { throw VolumeError.noDevice }
        let target = safe(value)
        guard shouldWrite(current: get(), target: target) else { return }
        var v = Float32(target)
        let size = UInt32(MemoryLayout<Float32>.size)
        var ok = false
        for ch: UInt32 in [0, 1, 2] {   // main, L, R — 지원되는 것만
            var a = volAddr(ch)
            if AudioObjectHasProperty(id, &a) {
                ok = AudioObjectSetPropertyData(id, &a, 0, nil, size, &v) == noErr || ok
            }
        }
        if !ok { throw VolumeError.setFailed }
    }
}
