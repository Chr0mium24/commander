import Foundation

struct GeminiStreamingService {
    static func streamResponse(
        prompt: String,
        apiKey: String,
        model: String,
        proxyURL: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard !apiKey.isEmpty else {
                    continuation.finish(throwing: NSError(
                        domain: "Gemini",
                        code: 401,
                        userInfo: [NSLocalizedDescriptionKey: "Please set Gemini API Key in Settings."]
                    ))
                    return
                }

                let baseURL = "https://generativelanguage.googleapis.com"
                let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
                let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
                let urlString = "\(baseURL)/v1beta/models/\(encodedModel):streamGenerateContent?key=\(encodedKey)&alt=sse"

                guard let url = URL(string: urlString) else {
                    continuation.finish(throwing: URLError(.badURL))
                    return
                }

                let session: URLSession
                if !proxyURL.isEmpty,
                   let proxy = URL(string: proxyURL),
                   let host = proxy.host,
                   let port = proxy.port {
                    let config = URLSessionConfiguration.default
                    config.connectionProxyDictionary = [
                        kCFNetworkProxiesHTTPEnable as String: true,
                        kCFNetworkProxiesHTTPProxy as String: host,
                        kCFNetworkProxiesHTTPPort as String: port,
                        kCFNetworkProxiesHTTPSEnable as String: true,
                        kCFNetworkProxiesHTTPSProxy as String: host,
                        kCFNetworkProxiesHTTPSPort as String: port
                    ]
                    session = URLSession(configuration: config)
                } else {
                    session = URLSession.shared
                }

                let body: [String: Any] = [
                    "contents": [
                        ["parts": [["text": prompt]]]
                    ]
                ]

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)

                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: URLError(.badServerResponse))
                        return
                    }

                    guard http.statusCode == 200 else {
                        continuation.finish(throwing: NSError(
                            domain: "Gemini",
                            code: http.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "Server error: \(http.statusCode)"]
                        ))
                        return
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
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
