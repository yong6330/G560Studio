import CoreAudio

/// G560 오디오 장치의 CoreAudio 출력 볼륨. HID++ 아님 (protocol.md).
public enum OutputVolume {
    public enum VolumeError: Error { case noDevice, setFailed }

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

    public static func set(_ value: Double) throws {
        guard let id = g560DeviceID() else { throw VolumeError.noDevice }
        var v = Float32(max(0, min(1, value)))
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
