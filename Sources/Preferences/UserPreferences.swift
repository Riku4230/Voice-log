import SwiftUI

// MARK: - Post-processing mode

enum PostProcessingMode: String, CaseIterable, Sendable {
    case local = "local"           // ルールベースのみ (無料)
    case claudeAPI = "claude"      // Claude Haiku API
    case ollama = "ollama"         // Ollama ローカル LLM
}

// MARK: - User Preferences

@MainActor
final class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    // Post-processing
    @AppStorage("postProcessingMode") var postProcessingMode: PostProcessingMode = .local
    @AppStorage("fillerRemovalEnabled") var fillerRemovalEnabled: Bool = true
    @AppStorage("bulletPointsEnabled") var bulletPointsEnabled: Bool = false

    // Claude API — stored in Keychain
    @Published var claudeApiKey: String = "" {
        didSet {
            KeychainHelper.save(key: "claudeApiKey", value: claudeApiKey)
        }
    }

    // Ollama
    @AppStorage("ollamaEndpoint") var ollamaEndpoint: String = "http://localhost:11434"
    @AppStorage("ollamaModel") var ollamaModel: String = "llama3.2:3b"

    // Hotkey (CGKeyCode as Int)
    @AppStorage("hotkeyCode") var hotkeyCode: Int = 63  // Fn

    // Transcription
    @AppStorage("transcriptionLocale") var transcriptionLocale: String = "ja-JP"

    // Microphone
    @AppStorage("inputSensitivity") var inputSensitivity: Double = 1.5  // 1.0〜3.0
    @AppStorage("voiceProcessingEnabled") var voiceProcessingEnabled: Bool = false

    // Behavior
    @AppStorage("llmTimeout") var llmTimeout: Double = 3.0
    @AppStorage("readyToPasteTimeout") var readyToPasteTimeout: Double = 300.0  // 5 min

    private init() {
        // Migrate from @AppStorage to Keychain (one-time)
        let legacyKey = UserDefaults.standard.string(forKey: "claudeApiKey") ?? ""
        if !legacyKey.isEmpty {
            KeychainHelper.save(key: "claudeApiKey", value: legacyKey)
            UserDefaults.standard.removeObject(forKey: "claudeApiKey")
        }

        // Load from Keychain
        claudeApiKey = KeychainHelper.load(key: "claudeApiKey")
    }
}

// Make PostProcessingMode conform to RawRepresentable for @AppStorage
extension PostProcessingMode: RawRepresentable {}
