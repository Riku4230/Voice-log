import Foundation

// MARK: - Post Processor

@MainActor
final class PostProcessor {

    private var currentTask: Task<String, Error>?

    // MARK: - Rule-based filler removal (instant, free)

    static let fillerPatterns: [String] = [
        "えーと", "えっと", "えー", "あのー", "あの", "まあ", "うー",
        "そのー", "なんか", "あのね", "えと", "うーん", "あー",
    ]

    static func removeFillers(_ text: String) -> String {
        var result = text
        for filler in fillerPatterns {
            result = result.replacingOccurrences(
                of: "\(filler)[、。,\\.\\s]?",
                with: "",
                options: [.regularExpression]
            )
        }
        result = result.replacingOccurrences(of: "、、", with: "、")
        result = result.replacingOccurrences(of: "。。", with: "。")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Process (optional LLM)

    func process(rawTranscript: String, preferences: UserPreferences, customInstructions: String = "") {
        currentTask?.cancel()

        let mode = preferences.postProcessingMode
        let fillerEnabled = preferences.fillerRemovalEnabled
        let bulletEnabled = preferences.bulletPointsEnabled
        let apiKey = preferences.claudeApiKey
        let ollamaEndpoint = preferences.ollamaEndpoint
        let ollamaModel = preferences.ollamaModel

        currentTask = Task {
            var text = rawTranscript

            if fillerEnabled {
                text = PostProcessor.removeFillers(text)
            }

            switch mode {
            case .local:
                break
            case .claudeAPI:
                guard !apiKey.isEmpty else { break }
                text = try await ClaudeClient.postProcess(
                    transcript: text, apiKey: apiKey, bulletPoints: bulletEnabled,
                    customInstructions: customInstructions
                )
            case .ollama:
                text = try await OllamaClient.postProcess(
                    transcript: text, endpoint: ollamaEndpoint,
                    model: ollamaModel, bulletPoints: bulletEnabled,
                    customInstructions: customInstructions
                )
            }

            return text
        }
    }

    func getResult(rawFallback: String, timeout: TimeInterval) async -> String {
        guard let task = currentTask else { return rawFallback }

        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await task.value }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw CancellationError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } catch {
            return rawFallback
        }
    }
}

// MARK: - Claude Client

enum ClaudeClient {
    static func postProcess(transcript: String, apiKey: String, bulletPoints: Bool, customInstructions: String = "") async throws -> String {
        var systemPrompt: String
        if bulletPoints {
            systemPrompt = "音声文字起こしテキストを整形してください。フィラーワードが残っていれば除去し、「・」始まりの箇条書きに変換。内容は変更せず、出力はテキストのみ。"
        } else {
            systemPrompt = "音声文字起こしテキストを自然な日本語に整形してください。フィラーワードが残っていれば除去し、文法を自然に整える。内容は変更せず、出力はテキストのみ。"
        }
        if !customInstructions.isEmpty {
            systemPrompt += "\n\n追加指示: \(customInstructions)"
        }

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 512,
            "system": systemPrompt,
            "messages": [["role": "user", "content": transcript]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw LLMError.httpError
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw LLMError.parseError
        }
        return text
    }
}

// MARK: - Ollama Client

enum OllamaClient {
    static func postProcess(transcript: String, endpoint: String, model: String, bulletPoints: Bool, customInstructions: String = "") async throws -> String {
        var prompt: String
        if bulletPoints {
            prompt = "以下のテキストを「・」始まりの箇条書きに変換してください。内容は変更せず、出力はテキストのみ：\n\n\(transcript)"
        } else {
            prompt = "以下の音声文字起こしテキストを自然な日本語に整形してください。フィラーが残っていれば除去し、出力はテキストのみ：\n\n\(transcript)"
        }
        if !customInstructions.isEmpty {
            prompt = "追加指示: \(customInstructions)\n\n" + prompt
        }

        let body: [String: Any] = ["model": model, "prompt": prompt, "stream": false]

        guard let url = URL(string: "\(endpoint)/api/generate"),
              let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw LLMError.httpError
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["response"] as? String else {
            throw LLMError.parseError
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LLMError: Error {
    case httpError
    case parseError
    case invalidURL
}
