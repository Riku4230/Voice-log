import Speech
import AVFoundation

// MARK: - Transcript Update

/// Updates are scoped to a single recognition session.
/// The caller (AppCoordinator) is responsible for accumulating text across sessions.
enum TranscriptUpdate {
    /// Partial result from current session (may change as recognition continues)
    case partial(String)
    /// Final result from current session — session is complete, text is stable
    case final_(String)

    var text: String {
        switch self {
        case .partial(let t), .final_(let t): return t
        }
    }

    var isFinal: Bool {
        if case .final_ = self { return true }
        return false
    }
}

// MARK: - Speech Recognizer (Apple on-device, real-time streaming)
//
// Each session reports only its OWN text — no cross-session accumulation.
// The caller accumulates text across sessions so even if a session dies,
// previously finalized text is never lost.

final class SpeechRecognizer {

    private let recognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var continuation: AsyncStream<TranscriptUpdate>.Continuation?
    private var isStopping = false

    /// Tracks partial text for the current session (salvaged on error)
    private var lastSessionPartialText = ""

    /// Prevents double-rotation when both isFinal and error fire for same session
    private var currentSessionID = UUID()

    /// Custom words to boost recognition accuracy
    private var contextualStrings: [String] = []

    /// Called when a new session starts — allows replaying recent audio buffers
    var onSessionRotation: (() -> Void)?

    init(locale: Locale = Locale(identifier: "ja-JP")) {
        guard let rec = SFSpeechRecognizer(locale: locale) else {
            fatalError("SFSpeechRecognizer not available for locale: \(locale.identifier)")
        }
        self.recognizer = rec
    }

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Recognition

    func startRecognition(contextualStrings: [String] = []) throws -> AsyncStream<TranscriptUpdate> {
        guard recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        isStopping = false
        lastSessionPartialText = ""
        currentSessionID = UUID()
        self.contextualStrings = contextualStrings

        let stream = AsyncStream<TranscriptUpdate> { [weak self] continuation in
            self?.continuation = continuation
            self?.startNewSession(continuation: continuation)
        }

        AppLogger.info("SpeechRecognizer started")
        return stream
    }

    private func startNewSession(continuation: AsyncStream<TranscriptUpdate>.Continuation) {
        guard !isStopping else { return }

        let sessionID = UUID()
        currentSessionID = sessionID
        lastSessionPartialText = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        if !contextualStrings.isEmpty {
            request.contextualStrings = contextualStrings
        }

        self.recognitionRequest = request

        // Replay recent audio into the new session to cover the rotation gap
        self.onSessionRotation?()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, !self.isStopping else { return }
            guard self.currentSessionID == sessionID else { return }

            if let result {
                let sessionText = result.bestTranscription.formattedString

                if result.isFinal {
                    self.lastSessionPartialText = ""
                    // Report session-scoped final text
                    continuation.yield(.final_(sessionText))
                    AppLogger.info("SpeechRecognizer: session ended via isFinal (\(sessionText.count) chars)")
                    self.startNewSession(continuation: continuation)
                    return
                } else {
                    self.lastSessionPartialText = sessionText
                    continuation.yield(.partial(sessionText))
                }
            }

            if let error = error as? NSError, !self.isStopping {
                guard self.currentSessionID == sessionID else { return }

                // Salvage partial text as final before rotating
                if !self.lastSessionPartialText.isEmpty {
                    continuation.yield(.final_(self.lastSessionPartialText))
                    AppLogger.info("SpeechRecognizer: salvaged \(self.lastSessionPartialText.count) chars on error \(error.code)")
                    self.lastSessionPartialText = ""
                }

                AppLogger.info("SpeechRecognizer: error \(error.code) (\(error.domain)), rotating session")
                self.startNewSession(continuation: continuation)
            }
        }
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    /// Replay buffered audio into the current recognition request (for session rotation)
    func replayBuffers(_ buffers: [AVAudioPCMBuffer]) {
        guard let request = recognitionRequest else { return }
        for buffer in buffers {
            request.append(buffer)
        }
        if !buffers.isEmpty {
            AppLogger.info("SpeechRecognizer: replayed \(buffers.count) buffers into new session")
        }
    }

    func stopRecognition() {
        isStopping = true
        recognitionRequest?.endAudio()
        AppLogger.info("SpeechRecognizer: endAudio")
    }

    func cancelRecognition() {
        isStopping = true
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        continuation?.finish()
        continuation = nil
    }
}

// MARK: - Errors

enum SpeechError: Error, LocalizedError {
    case recognizerUnavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "Speech recognizer is not available."
        case .permissionDenied:      return "Speech recognition permission denied."
        }
    }
}
