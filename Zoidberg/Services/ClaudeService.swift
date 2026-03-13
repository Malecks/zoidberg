// Zoidberg/Services/ClaudeService.swift
import Foundation

struct EnhanceResult {
    let title: String
    let folder: String
    let cleanedText: String?
}

final class ClaudeService {
    let apiKey: String?
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-haiku-4-5-20251001"
    private let timeout: TimeInterval = 30

    var isEnabled: Bool { apiKey != nil && !(apiKey?.isEmpty ?? true) }

    init(apiKey: String?) {
        self.apiKey = apiKey
    }

    func enhance(session: CaptureSession) async -> EnhanceResult? {
        guard isEnabled, let apiKey = apiKey else { return nil }

        let prompt = Self.buildEnhancePrompt(for: session)

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            return try Self.parseEnhanceResponse(data)
        } catch {
            return nil
        }
    }

    static func buildEnhancePrompt(for session: CaptureSession) -> String {
        let content = session.items.map { $0.toMarkdown() }.joined(separator: "\n")
        return """
        You are organizing a quick capture note for an Obsidian vault. \
        The user captured the following content:

        ---
        \(content)
        ---

        Respond with ONLY a JSON object (no markdown fencing) with these fields:
        - "title": A concise, descriptive title for this note (3-8 words)
        - "folder": A folder name for organizing this note (e.g. "Projects", "Ideas", "Research", "Tasks", "Personal")
        - "cleanedText": If the text appears to be dictated (run-on, missing punctuation), \
        clean it up with proper punctuation and paragraph breaks. If the text is already clean, \
        set this to null.
        """
    }

    static func parseEnhanceResponse(_ data: Data) throws -> EnhanceResult {
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = response["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw ClaudeServiceError.invalidResponse
        }
        guard let jsonData = text.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let title = result["title"] as? String,
              let folder = result["folder"] as? String else {
            throw ClaudeServiceError.invalidResponse
        }
        let cleanedText = result["cleanedText"] as? String
        return EnhanceResult(title: title, folder: folder, cleanedText: cleanedText)
    }
}

enum ClaudeServiceError: Error {
    case invalidResponse
}
