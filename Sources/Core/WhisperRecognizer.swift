import Foundation
import AVFoundation
import Accelerate
import SwiftWhisper

// MARK: - Whisper Recognizer (Local batch transcription via whisper.cpp)
//
// Provides high-accuracy batch transcription using whisper.cpp (via SwiftWhisper).
// Designed for use as a "final pass" after SFSpeech provides real-time partial results.
//
// Recommended models for Japanese:
//   - ggml-large-v3-turbo.bin  (~800MB, best speed/accuracy balance)
//   - ggml-medium.bin          (~1.5GB, good accuracy)
//   - ggml-small.bin           (~466MB, usable for Japanese)
//
// Models should be placed in: ~/Library/Application Support/VoiceLog/models/

final class WhisperRecognizer: @unchecked Sendable {

    private let lock = NSLock()
    private var whisper: Whisper?
    private var loadedModelName: String?

    // MARK: - Model Management

    /// Directory where model files are stored.
    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceLog/models", isDirectory: true)
    }

    /// Check if a model file exists locally.
    static func modelExists(name: String) -> Bool {
        let url = modelsDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// List available model files.
    static func availableModels() -> [String] {
        let dir = modelsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return []
        }
        return files.filter { $0.hasSuffix(".bin") }.sorted()
    }

    /// Ensure the models directory exists.
    static func ensureModelsDirectory() {
        let dir = modelsDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Load Model

    /// Load a Whisper model from the models directory.
    /// This is CPU-intensive and should be called from a background task.
    func loadModel(name: String, language: String = "ja") throws {
        let url = Self.modelsDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WhisperRecognizerError.modelNotFound(name)
        }

        AppLogger.info("WhisperRecognizer: loading model '\(name)'...")

        var params = WhisperParams(strategy: .greedy)
        params.language = WhisperLanguage(rawValue: language) ?? .japanese
        params.no_timestamps = true

        let w = Whisper(fromFileURL: url, withParams: params)
        lock.lock()
        self.whisper = w
        self.loadedModelName = name
        lock.unlock()
        AppLogger.info("WhisperRecognizer: model loaded successfully")
    }

    /// Whether a model is currently loaded and ready.
    var isReady: Bool {
        lock.lock()
        let ready = whisper != nil
        lock.unlock()
        return ready
    }

    // MARK: - Transcribe

    /// Transcribe audio samples using the loaded Whisper model.
    ///
    /// - Parameters:
    ///   - samples: Raw audio samples (mono, Float32)
    ///   - sampleRate: Sample rate of the input audio (will be resampled to 16kHz if needed)
    /// - Returns: Transcribed text
    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        lock.lock()
        let w = whisper
        lock.unlock()
        guard let w else {
            throw WhisperRecognizerError.modelNotLoaded
        }

        guard !samples.isEmpty else {
            return ""
        }

        // Resample to 16kHz (Whisper's expected sample rate)
        let targetRate: Double = 16000
        let resampled: [Float]
        if abs(sampleRate - targetRate) < 1.0 {
            resampled = samples
        } else {
            resampled = Self.resample(samples, from: sampleRate, to: targetRate)
        }

        AppLogger.info("WhisperRecognizer: transcribing \(resampled.count) samples (\(String(format: "%.1f", Double(resampled.count) / targetRate))s)")

        let segments = try await w.transcribe(audioFrames: resampled)
        let text = segments.map { $0.text }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        AppLogger.info("WhisperRecognizer: result = \(text.count) chars")
        return text
    }

    // MARK: - Audio Resampling

    /// Resample audio from one sample rate to another using linear interpolation.
    static func resample(_ samples: [Float], from sourceSR: Double, to targetSR: Double) -> [Float] {
        let ratio = targetSR / sourceSR
        let outputCount = Int(Double(samples.count) * ratio)
        guard outputCount > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputCount)

        // Use vDSP for efficient resampling via linear interpolation
        for i in 0..<outputCount {
            let srcIdx = Double(i) / ratio
            let idx0 = Int(srcIdx)
            let frac = Float(srcIdx - Double(idx0))

            if idx0 + 1 < samples.count {
                output[i] = samples[idx0] * (1.0 - frac) + samples[idx0 + 1] * frac
            } else if idx0 < samples.count {
                output[i] = samples[idx0]
            }
        }

        return output
    }
}

// MARK: - Errors

enum WhisperRecognizerError: Error, LocalizedError {
    case modelNotFound(String)
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Whisper model not found: \(name). Place model files in ~/Library/Application Support/VoiceLog/models/"
        case .modelNotLoaded:
            return "Whisper model not loaded. Call loadModel() first."
        }
    }
}
