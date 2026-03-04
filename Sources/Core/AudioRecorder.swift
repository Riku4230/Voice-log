import AVFoundation

// MARK: - Audio Recorder

final class AudioRecorder: @unchecked Sendable {

    private var engine: AVAudioEngine?
    private var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    /// Audio preprocessor for boosting quiet voice recognition
    private let audioPreprocessor = AudioPreprocessor()

    /// Ring buffer holding recent audio for replay on session rotation
    private let ringLock = NSLock()
    private var ringBuffers: [AVAudioPCMBuffer] = []
    private let maxRingSeconds: Double = 3.0
    private var ringSampleRate: Double = 48000.0

    func startRecording(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let engine = AVAudioEngine()
        self.engine = engine
        self.onBuffer = onBuffer

        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        ringSampleRate = nativeFormat.sampleRate

        ringLock.lock()
        ringBuffers.removeAll()
        ringLock.unlock()

        let preprocessor = self.audioPreprocessor
        preprocessor.prepare(sampleRate: nativeFormat.sampleRate, channelCount: Int(nativeFormat.channelCount))

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            preprocessor.process(buffer)
            self?.pushToRing(buffer)
            onBuffer(buffer)
        }

        try engine.start()
        AppLogger.info("AudioRecorder started (sampleRate=\(nativeFormat.sampleRate), preprocessing=enabled)")
    }

    /// Update the input sensitivity (output gain multiplier).
    func updateSensitivity(_ value: Double) {
        audioPreprocessor.config.outputGain = Float(value)
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
}
