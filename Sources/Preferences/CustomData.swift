import Foundation

// MARK: - Dictionary Word (boost recognition accuracy)

struct DictionaryWord: Codable, Identifiable, Equatable {
    let id: UUID
    var word: String

    init(word: String) {
        self.id = UUID()
        self.word = word
    }
}

// MARK: - Replacement Rule (trigger phrase → replacement text)

struct ReplacementRule: Codable, Identifiable, Equatable {
    let id: UUID
    var trigger: String
    var replacement: String

    init(trigger: String, replacement: String) {
        self.id = UUID()
        self.trigger = trigger
        self.replacement = replacement
    }
}

// MARK: - Custom Data Store

@MainActor
final class CustomData: ObservableObject {
    static let shared = CustomData()

    @Published var dictionaryWords: [DictionaryWord] = []
    @Published var replacementRules: [ReplacementRule] = []
    @Published var customInstructions: String = ""

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("VoiceLog", isDirectory: true)

        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.fileURL = appSupport.appendingPathComponent("custom_data.json")

        load()
    }

    // MARK: - Dictionary

    func addWord(_ word: String) {
        guard !word.isEmpty else { return }
        dictionaryWords.append(DictionaryWord(word: word))
        save()
    }

    func removeWord(id: UUID) {
        dictionaryWords.removeAll { $0.id == id }
        save()
    }

    // MARK: - Replacements

    func addReplacement(trigger: String, replacement: String) {
        guard !trigger.isEmpty else { return }
        replacementRules.append(ReplacementRule(trigger: trigger, replacement: replacement))
        save()
    }

    func removeReplacement(id: UUID) {
        replacementRules.removeAll { $0.id == id }
        save()
    }

    // MARK: - Apply replacements to text

    static func applyReplacements(_ text: String, rules: [ReplacementRule]) -> String {
        var result = text
        for rule in rules where !rule.trigger.isEmpty {
            result = result.replacingOccurrences(of: rule.trigger, with: rule.replacement)
        }
        return result
    }

    // MARK: - Save custom instructions

    func saveInstructions() {
        save()
    }

    // MARK: - Persistence

    private struct StorageModel: Codable {
        var dictionaryWords: [DictionaryWord]
        var replacementRules: [ReplacementRule]
        var customInstructions: String
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let model = try JSONDecoder().decode(StorageModel.self, from: data)
            dictionaryWords = model.dictionaryWords
            replacementRules = model.replacementRules
            customInstructions = model.customInstructions
        } catch {
            AppLogger.error("Failed to load custom data: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let model = StorageModel(
                dictionaryWords: dictionaryWords,
                replacementRules: replacementRules,
                customInstructions: customInstructions
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(model)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: fileURL.path
            )
        } catch {
            AppLogger.error("Failed to save custom data: \(error.localizedDescription)")
        }
    }
}
