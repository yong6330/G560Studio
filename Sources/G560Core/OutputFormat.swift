import CoreAudio

/// G560 출력 스트림의 물리 포맷 (오디오 MIDI 설정의 "포맷"과 동일). 장치 설정이라 즉시 적용, 프로필과 무관.
public enum OutputFormat {
    public struct Format: Identifiable, Hashable, Sendable {
        public let sampleRate: Double, bits: UInt32, channels: UInt32
        public var id: String { "\(channels)ch \(bits)bit \(Int(sampleRate))" }
        public var label: String { "\(channels)ch \(bits)비트 정수 \(String(format: "%.1f", sampleRate / 1000)) kHz" }
    }

    static func outputStream(_ dev: AudioObjectID) -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr, size > 0 else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &ids)
        return ids.first
    }

    public static func available() -> [Format] {
        guard let dev = OutputVolume.g560DeviceID(), let st = outputStream(dev) else { return [] }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyAvailablePhysicalFormats, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(st, &addr, 0, nil, &size) == noErr else { return [] }
        var list = [AudioStreamRangedDescription](repeating: AudioStreamRangedDescription(), count: Int(size) / MemoryLayout<AudioStreamRangedDescription>.size)
        AudioObjectGetPropertyData(st, &addr, 0, nil, &size, &list)
        var seen = Set<String>(); var out: [Format] = []
        for r in list where r.mFormat.mFormatID == kAudioFormatLinearPCM {
            let f = Format(sampleRate: r.mFormat.mSampleRate, bits: r.mFormat.mBitsPerChannel, channels: r.mFormat.mChannelsPerFrame)
            if seen.insert(f.id).inserted { out.append(f) }
        }
        return out.sorted { ($0.bits, $0.sampleRate) < ($1.bits, $1.sampleRate) }
    }

    public static func current() -> Format? {
        guard let dev = OutputVolume.g560DeviceID(), let st = outputStream(dev) else { return nil }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyPhysicalFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var d = AudioStreamBasicDescription(); var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(st, &addr, 0, nil, &size, &d) == noErr else { return nil }
        return Format(sampleRate: d.mSampleRate, bits: d.mBitsPerChannel, channels: d.mChannelsPerFrame)
    }

    public static func set(_ f: Format) -> Bool {
        guard let dev = OutputVolume.g560DeviceID(), let st = outputStream(dev) else { return false }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyAvailablePhysicalFormats, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(st, &addr, 0, nil, &size) == noErr else { return false }
        var list = [AudioStreamRangedDescription](repeating: AudioStreamRangedDescription(), count: Int(size) / MemoryLayout<AudioStreamRangedDescription>.size)
        AudioObjectGetPropertyData(st, &addr, 0, nil, &size, &list)
        // 장치가 제시한 정확한 descriptor를 그대로 쓴다 (플래그/바이트 수 등 임의 조합 금지)
        guard var d = list.first(where: { $0.mFormat.mSampleRate == f.sampleRate && $0.mFormat.mBitsPerChannel == f.bits && $0.mFormat.mChannelsPerFrame == f.channels })?.mFormat else { return false }
        addr.mSelector = kAudioStreamPropertyPhysicalFormat
        return AudioObjectSetPropertyData(st, &addr, 0, nil, UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &d) == noErr
    }
}
