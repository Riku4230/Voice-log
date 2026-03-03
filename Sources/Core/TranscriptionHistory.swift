import Foundation

// MARK: - Transcription Record

struct TranscriptionRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let rawTranscript: String
    let cleanedTranscript: String

    init(raw: String, cleaned: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.rawTranscript = raw
        self.cleanedTranscript = cleaned
    }

    init(id: UUID, timestamp: Date, raw: String, cleaned: String) {
        self.id = id
        self.timestamp = timestamp
        self.rawTranscript = raw
        self.cleanedTranscript = cleaned
    }
}

// MARK: - Transcription History

@MainActor
final class TranscriptionHistory: ObservableObject {
    static let shared = TranscriptionHistory()

    @Published private(set) var records: [TranscriptionRecord] = []

    private let fileURL: URL
    private let retentionDays = 10

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("VoiceLog", isDirectory: true)

        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.fileURL = appSupport.appendingPathComponent("history.json")

        load()
        pruneOldRecords()
    }

    // MARK: - Save

    func save(raw: String, cleaned: String) {
        let record = TranscriptionRecord(raw: raw, cleaned: cleaned)
        records.insert(record, at: 0)
        persist()
    }

    // MARK: - Delete

    func deleteRecord(id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Update

    func updateRecord(id: UUID, cleaned: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let old = records[index]
        records[index] = TranscriptionRecord(
            id: old.id,
            timestamp: old.timestamp,
            raw: old.rawTranscript,
            cleaned: cleaned
        )
        persist()
    }

    // MARK: - Query

    func records(lastDays: Int) -> [TranscriptionRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -lastDays, to: Date())!
        return records.filter { $0.timestamp >= cutoff }
    }

    // MARK: - Markdown Export

    static func exportMarkdown(_ records: [TranscriptionRecord]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let grouped = Dictionary(grouping: records) { record in
            dateFormatter.string(from: record.timestamp)
        }

        var markdown = ""
        for dateKey in grouped.keys.sorted().reversed() {
            markdown += "## \(dateKey)\n\n"
            let dayRecords = grouped[dateKey]!.sorted { $0.timestamp > $1.timestamp }
            for record in dayRecords {
                let time = timeFormatter.string(from: record.timestamp)
                markdown += "### \(time)\n\(record.cleanedTranscript)\n\n"
            }
        }
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([TranscriptionRecord].self, from: data)
        } catch {
            AppLogger.error("Failed to load history: \(error.localizedDescription)")
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: fileURL.path
            )
        } catch {
            AppLogger.error("Failed to save history: \(error.localizedDescription)")
        }
    }

    private func pruneOldRecords() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())!
        let before = records.count
        records.removeAll { $0.timestamp < cutoff }
        if records.count != before {
            persist()
        }
    }
}
