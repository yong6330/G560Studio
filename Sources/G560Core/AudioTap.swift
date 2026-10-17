import CoreAudio
import Foundation

/// 시스템 출력 전체를 Process Tap으로 읽어 AudioLevels를 흘린다. macOS 14.2+.
/// 첫 실행 시 "시스템 오디오 녹음" 권한 팝업 1회. 녹음/저장 없음 — 버퍼는 레벨 계산 후 버린다.
public final class AudioTap: @unchecked Sendable {
    public enum TapError: Error { case createTap(OSStatus), createAggregate(OSStatus), ioProc(OSStatus) }
    public var onLevels: (@Sendable (AudioLevels) -> Void)?
    public private(set) var isRunning = false

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var sampleRate: Float = 48000
    private var loggedFirst = false

    public init() {}

    public func start() throws {
        guard !isRunning else { return }
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        desc.name = "G560Studio"
        var st = AudioHardwareCreateProcessTap(desc, &tapID)
        guard st == noErr else { throw TapError.createTap(st) }

        var fmt = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &fmt)
        sampleRate = Float(fmt.mSampleRate)
        let channels = max(1, Int(fmt.mChannelsPerFrame))

        // 탭만 담은 집계 장치. 출력 장치를 서브 장치로 넣으면 생성/해제 때 장치가 재초기화되어 볼륨이 튈 수 있다.
        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "G560Studio Tap",
            kAudioAggregateDeviceUIDKey: "com.onestudio.G560Studio.tap",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: false,
                                              kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        st = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID)
        guard st == noErr else { stop(); throw TapError.createAggregate(st) }

        st = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil) { [weak self] _, inData, _, _, _ in
            guard let self, let buf = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData)).first,
                  let p = buf.mData?.assumingMemoryBound(to: Float.self) else { return }
            let frames = Int(buf.mDataByteSize) / MemoryLayout<Float>.size / channels
            guard frames > 0 else { return }
            var mono = [Float](repeating: 0, count: frames)          // 인터리브 → (L+R)/n
            for i in 0..<frames {
                var s: Float = 0
                for c in 0..<channels { s += p[i * channels + c] }
                mono[i] = s / Float(channels)
            }
            let l = LevelMeter.measure(mono, sampleRate: self.sampleRate)
            if !self.loggedFirst, l.rms > 0.001 { self.loggedFirst = true; samplerLog("audio tap first non-silent frame rms=\(l.rms)") }
            self.onLevels?(l)
        }
        guard st == noErr else { stop(); throw TapError.ioProc(st) }
        st = AudioDeviceStart(aggID, procID)
        guard st == noErr else { stop(); throw TapError.ioProc(st) }
        isRunning = true
    }

    public func stop() {
        if let p = procID, aggID != kAudioObjectUnknown {
            AudioDeviceStop(aggID, p); AudioDeviceDestroyIOProcID(aggID, p); procID = nil
        }
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID); aggID = kAudioObjectUnknown }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = kAudioObjectUnknown }
        isRunning = false
    }

    deinit { stop() }
}
