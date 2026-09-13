import Accelerate

public struct AudioLevels: Sendable, Equatable {
    public var rms: Float, peak: Float, low: Float, mid: Float, high: Float   // 모두 0…1
    public init(rms: Float, peak: Float, low: Float, mid: Float, high: Float) {
        self.rms = rms; self.peak = peak; self.low = low; self.mid = mid; self.high = high
    }
    public static let silence = AudioLevels(rms: 0, peak: 0, low: 0, mid: 0, high: 0)
}

/// 모노 샘플 버퍼 → 레벨. 마지막 256 샘플에 FFT 하나. 순수 함수.
public enum LevelMeter {
    static let n = 256
    static let log2n = vDSP_Length(8)
    nonisolated(unsafe) static let fft = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

    public static func measure(_ samples: [Float], sampleRate: Float) -> AudioLevels {
        guard samples.count >= n else { return .silence }
        var rms: Float = 0, peak: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        if peak < 1e-5 { return .silence }

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var frame = [Float](repeating: 0, count: n)
        vDSP_vmul(Array(samples.suffix(n)), 1, window, 1, &frame, 1, vDSP_Length(n))
        var re = [Float](repeating: 0, count: n / 2), im = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeBufferPointer { fp in
                    fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(fft, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
            }
        }
        let binHz = sampleRate / Float(n)
        func band(_ lo: Float, _ hi: Float) -> Float {
            let a = max(1, Int(lo / binHz)), b = min(n / 2 - 1, Int(hi / binHz))
            guard b >= a else { return 0 }
            var s: Float = 0
            vDSP_sve(Array(mags[a...b]), 1, &s, vDSP_Length(b - a + 1))
            return min(1, sqrt(s / Float(b - a + 1)) / Float(n) * 8)   // ponytail: 경험적 스케일, 감도 슬라이더로 보정
        }
        return AudioLevels(rms: min(1, rms), peak: min(1, peak),
                           low: band(20, 250), mid: band(250, 2000), high: band(2000, sampleRate / 2))
    }
}
