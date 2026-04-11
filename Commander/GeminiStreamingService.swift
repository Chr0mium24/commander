import Foundation
internal import UniformTypeIdentifiers

struct GeminiStreamingService {
    enum RequestKind: String, Sendable {
        case gemini
        case openAICompatible = "openai_compatible"
    }

    struct AIRequest: Sendable {
        let kind: RequestKind
        let provider: String
        let baseURL: String
        let apiKey: String
        let model: String
        let proxyURL: String
        let systemPrompt: String
    }

    static func resolveRequest(
        kind: String,
        provider: String,
        baseURL: String,
        apiKey: String,
        model: String,
        proxyURL: String,
        systemPrompt: String
    ) throws -> AIRequest {
        let normalizedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let requestKind: RequestKind
        if normalizedKind.isEmpty {
            let normalizedProviderForInference = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let trimmedBaseURLForInference = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedProviderForInference == "gemini" || (normalizedProviderForInference.isEmpty && trimmedBaseURLForInference.isEmpty) {
                requestKind = .gemini
            } else {
                requestKind = .openAICompatible
            }
        } else if let parsedKind = RequestKind(rawValue: normalizedKind) {
            requestKind = parsedKind
        } else {
            throw configurationError("AI request kind is missing or invalid. Check Python plugin output.")
        }

        let normalizedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedProvider = normalizedProvider.isEmpty
            ? (requestKind == .gemini ? "gemini" : "openai_compatible")
            : normalizedProvider

        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProxyURL = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        switch requestKind {
        case .gemini:
            let resolvedModel = trimmedModel.isEmpty ? "gemini-1.5-flash" : trimmedModel
            let resolvedBaseURL = trimmedBaseURL.isEmpty
                ? "https://generativelanguage.googleapis.com"
                : trimmedBaseURL
            guard !trimmedAPIKey.isEmpty else {
                throw configurationError("Please set Gemini API Key in Settings.")
            }
            return AIRequest(
                kind: .gemini,
                provider: resolvedProvider,
                baseURL: resolvedBaseURL,
                apiKey: trimmedAPIKey,
                model: resolvedModel,
                proxyURL: trimmedProxyURL,
                systemPrompt: trimmedSystemPrompt
            )

        case .openAICompatible:
            let resolvedBaseURL = trimmedBaseURL.isEmpty
                ? defaultOpenAIBaseURL(for: resolvedProvider)
                : trimmedBaseURL
            guard !resolvedBaseURL.isEmpty else {
                throw configurationError("Please set AI Base URL in Settings.")
            }
            guard !trimmedAPIKey.isEmpty else {
                throw configurationError("Please set AI API Key in Settings.")
            }
            guard !trimmedModel.isEmpty else {
                throw configurationError("Please set AI Model in Settings.")
            }
            return AIRequest(
                kind: .openAICompatible,
                provider: resolvedProvider,
                baseURL: resolvedBaseURL,
                apiKey: trimmedAPIKey,
                model: trimmedModel,
                proxyURL: trimmedProxyURL,
                systemPrompt: trimmedSystemPrompt
            )
        }
    }

    static func streamResponse(
        prompt: String,
        request: AIRequest,
        imagePaths: [String]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let images = try loadImageInputs(from: imagePaths)
                    switch request.kind {
                    case .gemini:
                        try await streamGemini(
                            prompt: prompt,
                            request: request,
                            images: images,
                            continuation: continuation
                        )
                    case .openAICompatible:
                        try await streamOpenAICompatible(
                            prompt: prompt,
                            request: request,
                            images: images,
                            continuation: continuation
                        )
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private extension GeminiStreamingService {
    struct ImageInput: Sendable {
        let mimeType: String
        let base64: String
    }

    static func defaultOpenAIBaseURL(for provider: String) -> String {
        _ = provider
        return "https://api.openai.com/v1/chat/completions"
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

    static func loadImageInputs(from imagePaths: [String]) throws -> [ImageInput] {
        try imagePaths.map { path in
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            let mimeType = inferMimeType(for: url)
            return ImageInput(mimeType: mimeType, base64: data.base64EncodedString())
        }
    }

    static func inferMimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }
        return "application/octet-stream"
    }

    static func streamGemini(
        prompt: String,
        request: AIRequest,
        images: [ImageInput],
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let encodedModel = request.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? request.model
        let encodedKey = request.apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? request.apiKey
        let urlString = "\(request.baseURL)/v1beta/models/\(encodedModel):streamGenerateContent?key=\(encodedKey)&alt=sse"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let body = geminiRequestBody(prompt: prompt, request: request, images: images)

        var requestObject = URLRequest(url: url)
        requestObject.httpMethod = "POST"
        requestObject.addValue("application/json", forHTTPHeaderField: "Content-Type")
        requestObject.httpBody = try JSONSerialization.data(withJSONObject: body)

        let session = makeSession(proxyURL: request.proxyURL)
        let (bytes, response) = try await session.bytes(for: requestObject)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard http.statusCode == 200 else {
            var bodyText = ""
            for try await line in bytes.lines {
                bodyText += line + "\n"
            }
            throw networkError(provider: request.provider, statusCode: http.statusCode, body: bodyText)
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

    static func geminiRequestBody(
        prompt: String,
        request: AIRequest,
        images: [ImageInput]
    ) -> [String: Any] {
        var parts: [[String: Any]] = [["text": prompt]]
        parts.append(
            contentsOf: images.map { image in
                [
                    "inline_data": [
                        "mime_type": image.mimeType,
                        "data": image.base64
                    ]
                ]
            }
        )

        var body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": parts
                ]
            ]
        ]

        if !request.systemPrompt.isEmpty {
            body["system_instruction"] = [
                "parts": [
                    ["text": request.systemPrompt]
                ]
            ]
        }

        return body
    }

    static func streamOpenAICompatible(
        prompt: String,
        request: AIRequest,
        images: [ImageInput],
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard let url = URL(string: request.baseURL) else {
            throw URLError(.badURL)
        }

        let body = openAICompatibleRequestBody(prompt: prompt, request: request, images: images)

        var requestObject = URLRequest(url: url)
        requestObject.httpMethod = "POST"
        requestObject.addValue("application/json", forHTTPHeaderField: "Content-Type")
        requestObject.addValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        requestObject.httpBody = try JSONSerialization.data(withJSONObject: body)

        let session = makeSession(proxyURL: request.proxyURL)
        let (bytes, response) = try await session.bytes(for: requestObject)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard http.statusCode == 200 else {
            var bodyText = ""
            for try await line in bytes.lines {
                bodyText += line + "\n"
            }
            throw networkError(provider: request.provider, statusCode: http.statusCode, body: bodyText)
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

    static func openAICompatibleRequestBody(
        prompt: String,
        request: AIRequest,
        images: [ImageInput]
    ) -> [String: Any] {
        var messages: [[String: Any]] = []

        if !request.systemPrompt.isEmpty {
            messages.append(
                [
                    "role": "system",
                    "content": request.systemPrompt
                ]
            )
        }

        if images.isEmpty {
            messages.append(
                [
                    "role": "user",
                    "content": prompt
                ]
            )
        } else {
            var content: [[String: Any]] = [
                [
                    "type": "text",
                    "text": prompt
                ]
            ]
            content.append(
                contentsOf: images.map { image in
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:\(image.mimeType);base64,\(image.base64)"
                        ]
                    ]
                }
            )

            messages.append(
                [
                    "role": "user",
                    "content": content
                ]
            )
        }

        return [
            "model": request.model,
            "messages": messages,
            "stream": true
        ]
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
