//
//  ClaudeAPIClient.swift
//  no laughing matter
//

import Foundation

actor ClaudeAPIClient {

    private let session = URLSession.shared
    private let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let batchesURL = URL(string: "https://api.anthropic.com/v1/messages/batches")!
    private let apiVersion = "2023-06-01"
    let model = "claude-haiku-4-5"

    // MARK: - Tool Schema for Structured Output

    /// Tool definition that forces Claude to return a structured LLMClassification.
    /// Includes cache_control on the tool so system prompt + tools are cached across batch requests.
    let classifyTool: [String: Any] = [
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
        ] as [String: Any],
        "cache_control": ["type": "ephemeral"]
    ]

    // MARK: - Single Message API (for test view)

    func classify(systemPrompt: String, userPrompt: String) async throws -> LLMClassification {
        guard let apiKey = APIKeyManager.load() else {
            throw ClaudeAPIError.missingAPIKey
        }

        let body = buildRequestBody(system: systemPrompt, user: userPrompt)
        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse("Not an HTTP response")
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw ClaudeAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
        return try parseMessageResponse(data: data)
    }

    // MARK: - Batch API

    /// Creates a message batch and returns the batch ID
    func createBatch(requests: [[String: Any]]) async throws -> BatchStatus {
        guard let apiKey = APIKeyManager.load() else {
            throw ClaudeAPIError.missingAPIKey
        }

        let body: [String: Any] = ["requests": requests]
        var request = URLRequest(url: batchesURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse("Not an HTTP response")
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw ClaudeAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return try JSONDecoder().decode(BatchStatus.self, from: data)
    }

    /// Retrieves the current status of a batch
    func retrieveBatch(id: String) async throws -> BatchStatus {
        guard let apiKey = APIKeyManager.load() else {
            throw ClaudeAPIError.missingAPIKey
        }

        let url = batchesURL.appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse("Not an HTTP response")
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw ClaudeAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return try JSONDecoder().decode(BatchStatus.self, from: data)
    }

    /// Cancels a batch
    func cancelBatch(id: String) async throws {
        guard let apiKey = APIKeyManager.load() else {
            throw ClaudeAPIError.missingAPIKey
        }

        let url = batchesURL.appendingPathComponent(id).appendingPathComponent("cancel")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return }
    }

    /// Fetches batch results from the results URL, returns JSONL lines parsed into results
    func fetchBatchResults(resultsURL: String) async throws -> [BatchResult] {
        guard let apiKey = APIKeyManager.load() else {
            throw ClaudeAPIError.missingAPIKey
        }
        guard let url = URL(string: resultsURL) else {
            throw ClaudeAPIError.invalidResponse("Invalid results URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse("Not an HTTP response")
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw ClaudeAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        // Parse JSONL: each line is a separate JSON object
        guard let text = String(data: data, encoding: .utf8) else {
            throw ClaudeAPIError.invalidResponse("Results not valid UTF-8")
        }

        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { line -> BatchResult? in
            guard let lineData = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(BatchResult.self, from: lineData)
        }
    }

    // MARK: - Batch Request Building

    /// Build a single batch request entry from system + user prompt
    func buildBatchRequest(customId: String, system: String, user: String) -> [String: Any] {
        [
            "custom_id": customId,
            "params": buildRequestBody(system: system, user: user)
        ]
    }

    // MARK: - Request Building

    private func buildRequestBody(system: String, user: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 512,
            "system": [
                [
                    "type": "text",
                    "text": system,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "messages": [
                ["role": "user", "content": user]
            ],
            "tools": [classifyTool],
            "tool_choice": ["type": "tool", "name": "classify_humor"]
        ] as [String: Any]
    }

    // MARK: - Response Parsing

    private func parseMessageResponse(data: Data) throws -> LLMClassification {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw ClaudeAPIError.invalidResponse("Missing content array")
        }

        guard let toolUse = content.first(where: { ($0["type"] as? String) == "tool_use" }),
              let input = toolUse["input"] as? [String: Any] else {
            throw ClaudeAPIError.invalidResponse("No tool_use block in response")
        }

        let inputData = try JSONSerialization.data(withJSONObject: input)
        return try JSONDecoder().decode(LLMClassification.self, from: inputData)
    }
}

// MARK: - Batch Models

struct BatchStatus: Codable {
    let id: String
    let processingStatus: String
    let requestCounts: RequestCounts
    let resultsUrl: String?
    let createdAt: String
    let endedAt: String?
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case processingStatus = "processing_status"
        case requestCounts = "request_counts"
        case resultsUrl = "results_url"
        case createdAt = "created_at"
        case endedAt = "ended_at"
        case expiresAt = "expires_at"
    }

    struct RequestCounts: Codable {
        let processing: Int
        let succeeded: Int
        let errored: Int
        let canceled: Int
        let expired: Int
    }
}

struct BatchResult: Codable {
    let customId: String
    let result: ResultBody

    enum CodingKeys: String, CodingKey {
        case customId = "custom_id"
        case result
    }

    struct ResultBody: Codable {
        let type: String           // "succeeded", "errored", "canceled", "expired"
        let message: MessageBody?  // only present when type == "succeeded"
    }

    struct MessageBody: Codable {
        let content: [ContentBlock]
    }

    struct ContentBlock: Codable {
        let type: String
        let input: [String: AnyCodableValue]?
    }

    /// Extract the LLMClassification from a succeeded result
    func classification() -> LLMClassification? {
        guard result.type == "succeeded",
              let content = result.message?.content,
              let toolUse = content.first(where: { $0.type == "tool_use" }),
              let input = toolUse.input else { return nil }

        // Convert AnyCodableValue dict back to JSON data for decoding
        let rawDict = input.mapValues { $0.rawValue }
        guard let data = try? JSONSerialization.data(withJSONObject: rawDict) else { return nil }
        return try? JSONDecoder().decode(LLMClassification.self, from: data)
    }
}

/// Type-erased Codable value for handling arbitrary JSON in tool_use input
enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    var rawValue: Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .null: return NSNull()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if container.decodeNil() { self = .null }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
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
    case batchFailed(String)

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
        case .batchFailed(let detail):
            return "Batch processing failed: \(detail)"
        }
    }
}
