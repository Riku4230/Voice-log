import AVFoundation
import Accelerate

// MARK: - Audio Preprocessor

/// Lightweight audio preprocessing pipeline to improve quiet voice recognition.
///
/// Pipeline: Highpass Filter (80Hz) → AGC → Output Gain + Soft Clip
///
/// All processing is done in-place on AVAudioPCMBuffer using vDSP for
/// near-zero CPU overhead on Apple Silicon.
final class AudioPreprocessor: @unchecked Sendable {

    // MARK: - Configuration

    struct Config {
        var isEnabled: Bool = true
        var highpassCutoff: Float = 80.0       // Hz — removes rumble below voice range
        var agcTargetRMS: Float = 0.1          // linear (~-20 dBFS)
        var agcAttackTime: Float = 0.010       // seconds — fast onset detection
        var agcReleaseTime: Float = 0.300      // seconds — slow decay to avoid pumping
        var agcMaxGainDB: Float = 30.0         // dB ceiling (~31.6x linear)
        var agcMinGainDB: Float = 0.0          // dB floor (1.0x — never attenuate)
        var outputGain: Float = 1.5            // user-configurable linear multiplier
        var clipCeiling: Float = 0.95          // soft-clip threshold
    }

    var config = Config()

    /// Current audio level (0.0-1.0) after processing. Read from main thread for UI.
    private(set) var currentLevel: Float = 0.0

    // MARK: - Internal State

    private var sampleRate: Float = 48000.0

    // Highpass filter state (single-pole IIR, per channel)
    private var hpCoeff: Float = 0.0
    private var hpPrevInput: [Float] = []
    private var hpPrevOutput: [Float] = []

    // AGC state
    private var smoothedGain: Float = 1.0
    private var agcMaxGainLinear: Float = 1.0
    private var agcMinGainLinear: Float = 1.0
    private var attackCoeff: Float = 0.0
    private var releaseCoeff: Float = 0.0

    // Noise floor estimation
    private var noiseFloor: Float = 0.0
    private var noiseFloorUpdateCount: Int = 0
    private let noiseFloorAlpha: Float = 0.01  // slow-tracking EMA for noise floor

    // MARK: - Prepare

    func prepare(sampleRate: Double, channelCount: Int = 1) {
        self.sampleRate = Float(sampleRate)

        // Highpass coefficient: single-pole IIR
        // coeff = exp(-2π × cutoff / sampleRate)
        hpCoeff = exp(-2.0 * .pi * config.highpassCutoff / self.sampleRate)
        hpPrevInput = [Float](repeating: 0.0, count: channelCount)
        hpPrevOutput = [Float](repeating: 0.0, count: channelCount)

        // AGC
        smoothedGain = 1.0
        currentLevel = 0.0
        noiseFloor = 0.0
        noiseFloorUpdateCount = 0
        agcMaxGainLinear = powf(10.0, config.agcMaxGainDB / 20.0)
        agcMinGainLinear = powf(10.0, config.agcMinGainDB / 20.0)

        // Smoothing coefficients: coeff = exp(-1 / (time × sampleRate / bufferSize))
        // Using approximate bufferSize of 1024
        let buffersPerSecond = self.sampleRate / 1024.0
        attackCoeff = exp(-1.0 / (config.agcAttackTime * buffersPerSecond))
        releaseCoeff = exp(-1.0 / (config.agcReleaseTime * buffersPerSecond))
    }

    // MARK: - Process

    func process(_ buffer: AVAudioPCMBuffer) {
        guard config.isEnabled else { return }
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        let channelCount = Int(buffer.format.channelCount)

        for ch in 0..<channelCount {
            let samples = channelData[ch]
            applyHighpass(samples, count: frameCount, channel: ch)
        }

        // AGC operates on channel 0 RMS but applies gain to all channels
        let gain = calculateAGCGain(channelData[0], count: frameCount)

        for ch in 0..<channelCount {
            let samples = channelData[ch]
            applyGainAndClip(samples, count: frameCount, gain: gain)
        }
    }

    // MARK: - Highpass Filter

    /// Single-pole IIR highpass filter (DC-blocking / rumble removal).
    /// y[n] = coeff × (y[n-1] + x[n] - x[n-1])
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

    // MARK: - AGC

    /// Calculate smoothed gain based on buffer RMS level.
    private func calculateAGCGain(_ samples: UnsafeMutablePointer<Float>, count: Int) -> Float {
        // Calculate RMS using vDSP
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))

        // Update noise floor estimate (slow-tracking minimum)
        noiseFloorUpdateCount += 1
        if noiseFloorUpdateCount < 20 {
            // First ~0.4s: bootstrap noise floor from initial buffers
            noiseFloor = noiseFloorUpdateCount == 1 ? rms : min(noiseFloor, rms)
        } else if rms < noiseFloor * 1.5 {
            // Track noise floor upward slowly when signal is near floor level
            noiseFloor = noiseFloor * (1.0 - noiseFloorAlpha) + rms * noiseFloorAlpha
        } else if rms < noiseFloor {
            // Allow noise floor to decrease quickly
            noiseFloor = rms
        }

        // Update current level for UI (normalized 0-1, post-filter pre-gain)
        // Use log scale: map -60dBFS..0dBFS to 0..1
        let dbFS = rms > 1e-8 ? 20.0 * log10f(rms) : -60.0
        currentLevel = max(0.0, min(1.0, (dbFS + 60.0) / 60.0))

        // Avoid division by zero for silent buffers
        guard rms > 1e-8 else { return smoothedGain }

        // Skip AGC boost if signal is at noise floor (avoid amplifying pure noise)
        let isNoise = rms < noiseFloor * 2.0 && noiseFloorUpdateCount > 20
        if isNoise {
            // Gradually reduce gain toward 1.0 when only noise is present
            let coeff = releaseCoeff
            smoothedGain = coeff * smoothedGain + (1.0 - coeff) * 1.0
            return smoothedGain
        }

        // Calculate desired gain
        var desiredGain = config.agcTargetRMS / rms

        // Clamp to [minGain, maxGain]
        desiredGain = min(max(desiredGain, agcMinGainLinear), agcMaxGainLinear)

        // Smooth gain with asymmetric attack/release
        let coeff = desiredGain < smoothedGain ? attackCoeff : releaseCoeff
        smoothedGain = coeff * smoothedGain + (1.0 - coeff) * desiredGain

        return smoothedGain
    }

    // MARK: - Output Gain + Soft Clip

    /// Apply gain (AGC + user sensitivity) and clip to prevent digital clipping.
    private func applyGainAndClip(_ samples: UnsafeMutablePointer<Float>, count: Int, gain: Float) {
        let totalGain = gain * config.outputGain

        // Apply gain: vDSP_vsmul(input, stride, scalar, output, stride, count)
        var g = totalGain
        vDSP_vsmul(samples, 1, &g, samples, 1, vDSP_Length(count))

        // Clip to [-ceiling, +ceiling]: vDSP_vclip(input, stride, low, high, output, stride, count)
        var lo = -config.clipCeiling
        var hi = config.clipCeiling
        vDSP_vclip(samples, 1, &lo, &hi, samples, 1, vDSP_Length(count))
    }
}
