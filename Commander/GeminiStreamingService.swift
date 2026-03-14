import Foundation

struct GeminiStreamingService {
    static func streamResponse(
        prompt: String,
        geminiApiKey: String,
        geminiModel: String,
        proxyURL: String,
        aiProvider: String,
        aiBaseURL: String,
        aiApiKey: String,
        aiModel: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let resolved = try resolveProviderConfig(
                        geminiApiKey: geminiApiKey,
                        geminiModel: geminiModel,
                        aiProvider: aiProvider,
                        aiBaseURL: aiBaseURL,
                        aiApiKey: aiApiKey,
                        aiModel: aiModel
                    )

                    switch resolved.kind {
                    case .gemini:
                        try await streamGemini(prompt: prompt, config: resolved, proxyURL: proxyURL, continuation: continuation)
                    case .openAICompatible:
                        try await streamOpenAICompatible(prompt: prompt, config: resolved, proxyURL: proxyURL, continuation: continuation)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private extension GeminiStreamingService {
    enum AIProviderKind {
        case gemini
        case openAICompatible
    }

    struct ResolvedProviderConfig {
        let kind: AIProviderKind
        let provider: String
        let baseURL: String
        let apiKey: String
        let model: String
    }

    static func resolveProviderConfig(
        geminiApiKey: String,
        geminiModel: String,
        aiProvider: String,
        aiBaseURL: String,
        aiApiKey: String,
        aiModel: String
    ) throws -> ResolvedProviderConfig {
        let normalizedProvider = aiProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedBaseURL = aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        let useGemini = normalizedProvider.isEmpty
            ? trimmedBaseURL.isEmpty
            : normalizedProvider == "gemini"

        if useGemini {
            let apiKey = geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                throw configurationError("Please set Gemini API Key in Settings.")
            }

            let model = geminiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "gemini-1.5-flash"
                : geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)

            return ResolvedProviderConfig(
                kind: .gemini,
                provider: "gemini",
                baseURL: "https://generativelanguage.googleapis.com",
                apiKey: apiKey,
                model: model
            )
        }

        let provider = normalizedProvider.isEmpty ? "openai_compatible" : normalizedProvider
        let baseURL = trimmedBaseURL.isEmpty ? defaultOpenAIBaseURL(for: provider) : trimmedBaseURL
        let apiKey = aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = aiModel.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseURL.isEmpty else {
            throw configurationError("Please set AI Base URL in Settings.")
        }
        guard !apiKey.isEmpty else {
            throw configurationError("Please set AI API Key in Settings.")
        }
        guard !model.isEmpty else {
            throw configurationError("Please set AI Model in Settings.")
        }

        return ResolvedProviderConfig(
            kind: .openAICompatible,
            provider: provider,
            baseURL: baseURL,
            apiKey: apiKey,
            model: model
        )
    }

    static func defaultOpenAIBaseURL(for provider: String) -> String {
        switch provider {
        case "edge", "edgefn":
            return "https://api.edgefn.net/v1/chat/completions"
        default:
            return "https://api.openai.com/v1/chat/completions"
        }
    }

    static func makeSession(proxyURL: String) -> URLSession {
        let trimmed = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let proxy = URL(string: trimmed),
              let host = proxy.host,
              let port = proxy.port
        else {
            return .shared
        }

        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: host,
            kCFNetworkProxiesHTTPPort as String: port,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: host,
            kCFNetworkProxiesHTTPSPort as String: port
        ]
        return URLSession(configuration: config)
    }

    static func streamGemini(
        prompt: String,
        config: ResolvedProviderConfig,
        proxyURL: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let encodedModel = config.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.model
        let encodedKey = config.apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? config.apiKey
        let urlString = "\(config.baseURL)/v1beta/models/\(encodedModel):streamGenerateContent?key=\(encodedKey)&alt=sse"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let session = makeSession(proxyURL: proxyURL)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard http.statusCode == 200 else {
            var bodyText = ""
            for try await line in bytes.lines {
                bodyText += line + "\n"
            }
            throw networkError(provider: config.provider, statusCode: http.statusCode, body: bodyText)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let raw = String(line.dropFirst(6))
            if raw == "[DONE]" { break }

            guard let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = object["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                continue
            }

            let chunk = parts.compactMap { $0["text"] as? String }.joined()
            if !chunk.isEmpty {
                continuation.yield(chunk)
            }
        }

        continuation.finish()
    }

    static func streamOpenAICompatible(
        prompt: String,
        config: ResolvedProviderConfig,
        proxyURL: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard let url = URL(string: config.baseURL) else {
            throw URLError(.badURL)
        }

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "stream": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let session = makeSession(proxyURL: proxyURL)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard http.statusCode == 200 else {
            var bodyText = ""
            for try await line in bytes.lines {
                bodyText += line + "\n"
            }
            throw networkError(provider: config.provider, statusCode: http.statusCode, body: bodyText)
        }

        var didYieldChunk = false
        var nonSSEPayload = ""

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("data:") {
                var payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if payload.hasPrefix(":") {
                    payload.removeFirst()
                    payload = payload.trimmingCharacters(in: .whitespaces)
                }
                if payload == "[DONE]" {
                    break
                }

                let chunk = extractOpenAIContent(rawJSON: payload)
                if !chunk.isEmpty {
                    didYieldChunk = true
                    continuation.yield(chunk)
                }
            } else {
                nonSSEPayload += line
            }
        }

        if !didYieldChunk {
            let fallback = extractOpenAIContent(rawJSON: nonSSEPayload)
            if !fallback.isEmpty {
                continuation.yield(fallback)
            }
        }

        continuation.finish()
    }

    static func extractOpenAIContent(rawJSON: String) -> String {
        guard let data = rawJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ""
        }

        if let choices = object["choices"] as? [[String: Any]],
           let first = choices.first {
            if let delta = first["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                return content
            }
            if let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
            if let text = first["text"] as? String {
                return text
            }
        }

        if let output = object["output"] as? String {
            return output
        }

        return ""
    }

    static func configurationError(_ message: String) -> NSError {
        NSError(
            domain: "CommanderAI",
            code: 400,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    static func networkError(provider: String, statusCode: Int, body: String) -> NSError {
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = normalizedBody.isEmpty ? "" : "\n\(normalizedBody)"
        return NSError(
            domain: "CommanderAI",
            code: statusCode,
            userInfo: [
                NSLocalizedDescriptionKey: "\(provider) request failed (\(statusCode)).\(suffix)"
            ]
        )
    }
}
