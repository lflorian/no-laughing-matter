//
//  ClaudeAPIClient.swift
//  no laughing matter
//

import Foundation

actor ClaudeAPIClient {

    private let session = URLSession.shared
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let model = "claude-haiku-4-5"

    // Rate limiting: track request timestamps for 1000 RPM
    private var requestTimestamps: [Date] = []
    private let maxRequestsPerMinute = 1000

    // MARK: - Tool Schema for Structured Output

    /// Tool definition that forces Claude to return a structured LLMClassification
    private let classifyTool: [String: Any] = [
        "name": "classify_humor",
        "description": "Klassifiziere die Humorfunktion eines parlamentarischen Humorereignisses.",
        "input_schema": [
            "type": "object",
            "properties": [
                "primaryIntention": [
                    "type": "string",
                    "enum": ["aggressive", "social", "defensive", "intellectual", "sexual", "unclear"],
                    "description": "Die dominante Humorfunktion nach Zivs Modell."
                ],
                "secondaryIntention": [
                    "type": "string",
                    "enum": ["aggressive", "social", "defensive", "intellectual", "sexual"],
                    "description": "Optionale sekundäre Humorfunktion, nur wenn eine zweite Funktion klar erkennbar ist. Muss sich von primaryIntention unterscheiden. Weglassen, wenn der Humor monofunktional ist."
                ],
                "confidenceRating": [
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 10,
                    "description": "Konfidenz der Klassifikation von 1 (sehr niedrig) bis 10 (sehr hoch). Unsicherheit ist kein Problem, Ehrlichkeit ist erwünscht."
                ],
                "reasoning": [
                    "type": "string",
                    "description": "Knappe Begründung der Klassifikation. Konkreten Textbeleg nennen und erklären, warum diese Funktion und nicht die nächstliegende Alternative zutrifft."
                ]
            ],
            "required": ["primaryIntention", "confidenceRating", "reasoning"]
        ] as [String: Any]
    ]

    // MARK: - Public API

    func classify(systemPrompt: String, userPrompt: String) async throws -> LLMClassification {
        guard let apiKey = APIKeyManager.load() else {
            throw ClaudeAPIError.missingAPIKey
        }

        try await waitForRateLimit()

        let body = buildRequestBody(system: systemPrompt, user: userPrompt)
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await sendWithRetry(request: request, maxRetries: 3)
    }

    // MARK: - Request Building

    private func buildRequestBody(system: String, user: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 512,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ],
            "tools": [classifyTool],
            "tool_choice": ["type": "tool", "name": "classify_humor"]
        ] as [String: Any]
    }

    // MARK: - Response Parsing

    private func parseResponse(data: Data) throws -> LLMClassification {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw ClaudeAPIError.invalidResponse("Missing content array")
        }

        // Find the tool_use block
        guard let toolUse = content.first(where: { ($0["type"] as? String) == "tool_use" }),
              let input = toolUse["input"] as? [String: Any] else {
            throw ClaudeAPIError.invalidResponse("No tool_use block in response")
        }

        // Decode the input into LLMClassification
        let inputData = try JSONSerialization.data(withJSONObject: input)
        return try JSONDecoder().decode(LLMClassification.self, from: inputData)
    }

    // MARK: - Retry Logic

    private func sendWithRetry(request: URLRequest, maxRetries: Int) async throws -> LLMClassification {
        var lastError: Error?

        for attempt in 0...maxRetries {
            if attempt > 0 {
                // Exponential backoff: 1s, 2s, 4s
                try await Task.sleep(for: .seconds(pow(2.0, Double(attempt - 1))))
            }

            do {
                let (data, response) = try await session.data(for: request)
                recordRequest()

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ClaudeAPIError.invalidResponse("Not an HTTP response")
                }

                switch httpResponse.statusCode {
                case 200:
                    return try parseResponse(data: data)
                case 401:
                    throw ClaudeAPIError.unauthorized
                case 429:
                    // Rate limited — retry with backoff
                    lastError = ClaudeAPIError.rateLimited
                    continue
                case 529:
                    // Overloaded — retry with backoff
                    lastError = ClaudeAPIError.overloaded
                    continue
                default:
                    let body = String(data: data, encoding: .utf8) ?? "unknown"
                    throw ClaudeAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
                }
            } catch let error as ClaudeAPIError {
                switch error {
                case .rateLimited, .overloaded:
                    lastError = error
                    continue
                default:
                    throw error
                }
            } catch {
                lastError = error
                if attempt == maxRetries { throw error }
            }
        }

        throw lastError ?? ClaudeAPIError.invalidResponse("Max retries exceeded")
    }

    // MARK: - Rate Limiting

    private func recordRequest() {
        requestTimestamps.append(Date())
    }

    private func waitForRateLimit() async throws {
        // Clean up timestamps older than 60 seconds
        let cutoff = Date().addingTimeInterval(-60)
        requestTimestamps.removeAll { $0 < cutoff }

        if requestTimestamps.count >= maxRequestsPerMinute {
            // Wait until the oldest request in the window expires
            guard let oldest = requestTimestamps.first else { return }
            let waitTime = oldest.timeIntervalSince(cutoff)
            if waitTime > 0 {
                try await Task.sleep(for: .seconds(waitTime))
            }
            // Clean up again
            let newCutoff = Date().addingTimeInterval(-60)
            requestTimestamps.removeAll { $0 < newCutoff }
        }
    }
}

// MARK: - Errors

enum ClaudeAPIError: LocalizedError {
    case missingAPIKey
    case unauthorized
    case rateLimited
    case overloaded
    case httpError(statusCode: Int, body: String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key configured. Please add your Claude API key in Settings."
        case .unauthorized:
            return "Invalid API key. Please check your Claude API key in Settings."
        case .rateLimited:
            return "Rate limited by Claude API. Retrying..."
        case .overloaded:
            return "Claude API is overloaded. Retrying..."
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .invalidResponse(let detail):
            return "Invalid API response: \(detail)"
        }
    }
}
