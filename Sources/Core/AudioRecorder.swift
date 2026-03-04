import AVFoundation

// MARK: - Audio Recorder

final class AudioRecorder: @unchecked Sendable {

    private var engine: AVAudioEngine?
    private var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    /// Audio preprocessor (highpass filter + user sensitivity gain)
    private let audioPreprocessor = AudioPreprocessor()

    /// Ring buffer holding recent audio for replay on session rotation
    private let ringLock = NSLock()
    private var ringBuffers: [AVAudioPCMBuffer] = []
    private let maxRingSeconds: Double = 3.0
    private(set) var ringSampleRate: Double = 48000.0

    /// Accumulated raw audio samples for Whisper batch processing (mono, channel 0)
    private let whisperLock = NSLock()
    private var whisperSamples: [Float] = []

    func startRecording(voiceProcessing: Bool = false, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let engine = AVAudioEngine()
        self.engine = engine
        self.onBuffer = onBuffer

        let inputNode = engine.inputNode

        // Enable Apple's built-in voice processing (AGC + noise suppression)
        if voiceProcessing {
            if inputNode.isVoiceProcessingEnabled != true {
                do {
                    try inputNode.setVoiceProcessingEnabled(true)
                    AppLogger.info("Voice Processing IO enabled")
                } catch {
                    AppLogger.warning("Voice Processing IO failed: \(error.localizedDescription)")
                }
            }
        }

        let nativeFormat = inputNode.outputFormat(forBus: 0)
        ringSampleRate = nativeFormat.sampleRate

        ringLock.lock()
        ringBuffers.removeAll()
        ringLock.unlock()

        whisperLock.lock()
        whisperSamples.removeAll()
        whisperLock.unlock()

        let preprocessor = self.audioPreprocessor
        preprocessor.prepare(sampleRate: nativeFormat.sampleRate, channelCount: Int(nativeFormat.channelCount))

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            // Accumulate raw audio for Whisper (before processing)
            self?.accumulateForWhisper(buffer)

            // Process for SFSpeech (highpass + gain, no AGC)
            preprocessor.process(buffer)
            self?.pushToRing(buffer)
            onBuffer(buffer)
        }

        try engine.start()
        AppLogger.info("AudioRecorder started (sampleRate=\(nativeFormat.sampleRate), voiceProcessing=\(voiceProcessing))")
    }

    /// Update the input sensitivity (output gain multiplier).
    func updateSensitivity(_ value: Double) {
        audioPreprocessor.config.outputGain = Float(value)
    }

    /// Current audio level (0.0-1.0) for UI display.
    var currentAudioLevel: Float {
        audioPreprocessor.currentLevel
    }

    func stopRecording() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        onBuffer = nil
        ringLock.lock()
        ringBuffers.removeAll()
        ringLock.unlock()
        AppLogger.info("AudioRecorder stopped")
    }

    // MARK: - Ring Buffer

    private func pushToRing(_ buffer: AVAudioPCMBuffer) {
        ringLock.lock()
        ringBuffers.append(buffer)

        // Trim to maxRingSeconds
        var totalFrames: AVAudioFrameCount = 0
        for b in ringBuffers { totalFrames += b.frameLength }
        let maxFrames = AVAudioFrameCount(maxRingSeconds * ringSampleRate)
        while totalFrames > maxFrames, !ringBuffers.isEmpty {
            totalFrames -= ringBuffers.removeFirst().frameLength
        }
        ringLock.unlock()
    }

    /// Get a snapshot of recent audio buffers for replay into a new session
    func recentBuffers() -> [AVAudioPCMBuffer] {
        ringLock.lock()
        let copy = ringBuffers
        ringLock.unlock()
        return copy
    }

    // MARK: - Whisper Audio Accumulation

    /// Store raw audio samples (channel 0, mono) for Whisper batch processing.
    private func accumulateForWhisper(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        whisperLock.lock()
        let ptr = channelData[0]
        whisperSamples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: frameCount))
        whisperLock.unlock()
    }

    /// Get all accumulated raw audio samples and the recording sample rate.
    /// Call after stopRecording().
    func getRecordedSamples() -> [Float] {
        whisperLock.lock()
        let copy = whisperSamples
        whisperLock.unlock()
        return copy
    }

    /// Clear accumulated Whisper audio (called when starting a new recording).
    func clearRecordedSamples() {
        whisperLock.lock()
        whisperSamples.removeAll()
        whisperLock.unlock()
    }
}
