import AVFoundation
import Accelerate

// MARK: - Audio Preprocessor
//
// Lightweight audio preprocessing for voice recognition.
//
// Pipeline: Highpass Filter (80Hz) -> User Sensitivity Gain
//
// AGC has been intentionally removed from the recognition path.
// Research shows that AGC's attack/release dynamics distort the audio signal
// and reduce recognition accuracy, especially for quiet/whispered speech.
// Instead, a simple user-configurable gain is applied.

final class AudioPreprocessor: @unchecked Sendable {

    // MARK: - Configuration

    struct Config {
        var isEnabled: Bool = true
        var highpassCutoff: Float = 80.0       // Hz — removes rumble below voice range
        var outputGain: Float = 1.5            // user-configurable linear multiplier (sensitivity)
    }

    var config = Config()

    /// Current audio level (0.0-1.0) after highpass. Read from main thread for UI.
    private(set) var currentLevel: Float = 0.0

    // MARK: - Internal State

    private var sampleRate: Float = 48000.0

    // Highpass filter state (single-pole IIR, per channel)
    private var hpCoeff: Float = 0.0
    private var hpPrevInput: [Float] = []
    private var hpPrevOutput: [Float] = []

    // MARK: - Prepare

    func prepare(sampleRate: Double, channelCount: Int = 1) {
        self.sampleRate = Float(sampleRate)

        // Highpass coefficient: single-pole IIR
        // coeff = exp(-2pi * cutoff / sampleRate)
        hpCoeff = exp(-2.0 * .pi * config.highpassCutoff / self.sampleRate)
        hpPrevInput = [Float](repeating: 0.0, count: channelCount)
        hpPrevOutput = [Float](repeating: 0.0, count: channelCount)
        currentLevel = 0.0
    }

    // MARK: - Process

    /// Process audio for recognition: highpass filter + user sensitivity gain.
    /// No AGC or clipping — preserves natural dynamics for better recognition accuracy.
    func process(_ buffer: AVAudioPCMBuffer) {
        guard config.isEnabled else { return }
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        let channelCount = Int(buffer.format.channelCount)

        // 1. Apply highpass filter (remove DC offset and rumble)
        for ch in 0..<channelCount {
            applyHighpass(channelData[ch], count: frameCount, channel: ch)
        }

        // 2. Compute level for UI (post-highpass, pre-gain)
        var rms: Float = 0.0
        vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(frameCount))
        let dbFS = rms > 1e-8 ? 20.0 * log10f(rms) : -60.0
        currentLevel = max(0.0, min(1.0, (dbFS + 60.0) / 60.0))

        // 3. Apply user sensitivity gain (simple linear, no AGC)
        if config.outputGain != 1.0 {
            for ch in 0..<channelCount {
                var gain = config.outputGain
                vDSP_vsmul(channelData[ch], 1, &gain, channelData[ch], 1, vDSP_Length(frameCount))
            }
        }
    }

    // MARK: - Highpass Filter

    /// Single-pole IIR highpass filter (DC-blocking / rumble removal).
    /// y[n] = coeff * (y[n-1] + x[n] - x[n-1])
    private func applyHighpass(_ samples: UnsafeMutablePointer<Float>, count: Int, channel: Int) {
        guard channel < hpPrevInput.count else { return }

        var prevIn = hpPrevInput[channel]
        var prevOut = hpPrevOutput[channel]
        let c = hpCoeff

        for i in 0..<count {
            let x = samples[i]
            let y = c * (prevOut + x - prevIn)
            samples[i] = y
            prevIn = x
            prevOut = y
        }

        hpPrevInput[channel] = prevIn
        hpPrevOutput[channel] = prevOut
    }
}
