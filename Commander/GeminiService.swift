import Foundation

struct GeminiService {
    // 保持原有的 fetchResponse 用于非流式或其他用途（可选），或者直接保留作为备用
    static func fetchResponse(query: String, apiKey: String, model: String) async throws -> String {
        // ... (如果你想保留原有一次性请求代码，保持不变，否则可以删除)
        // 为节省篇幅，这里略过原有代码，重点在下面新增的方法
        return ""
    }

    // [新增] 流式生成方法
    static func streamResponse(query: String, apiKey: String, model: String) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard !apiKey.isEmpty else {
                    continuation.finish(throwing: NSError(domain: "Gemini", code: 401, userInfo: [NSLocalizedDescriptionKey: "⚠️ Please set your Gemini API Key in Settings."]))
                    return
                }

                let baseUrlString = "https://generativelanguage.googleapis.com"
                // 注意：这里使用 streamGenerateContent 并且加上 alt=sse
                let urlString = "\(baseUrlString)/v1beta/models/\(model):streamGenerateContent?key=\(apiKey)&alt=sse"
                
                guard let url = URL(string: urlString) else {
                    continuation.finish(throwing: URLError(.badURL))
                    return
                }

                // 获取代理设置
                let proxyString = UserDefaults.standard.string(forKey: AppStorageKey.geminiProxy) ?? ""
                let session: URLSession
                if !proxyString.isEmpty, let proxyUrl = URL(string: proxyString), let host = proxyUrl.host, let port = proxyUrl.port {
                    let config = URLSessionConfiguration.default
                    config.connectionProxyDictionary = [
                        kCFNetworkProxiesHTTPEnable: true,
                        kCFNetworkProxiesHTTPProxy: host,
                        kCFNetworkProxiesHTTPPort: port,
                        kCFNetworkProxiesHTTPSEnable: true,
                        kCFNetworkProxiesHTTPSProxy: host,
                        kCFNetworkProxiesHTTPSPort: port
                    ]
                    session = URLSession(configuration: config)
                } else {
                    session = URLSession.shared
                }

                // 构建请求
                let json: [String: Any] = [
                    "contents": [
                        ["parts": [["text": query]]]
                    ]
                ]

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: json)

                do {
                    // 使用 bytes(for:) 进行流式读取
                    let (bytes, response) = try await session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                        throw NSError(domain: "Gemini", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(statusCode)"])
                    }

                    for try await line in bytes.lines {
                        // SSE 格式是以 "data: " 开头的
                        if line.hasPrefix("data: ") {
                            let jsonStr = String(line.dropFirst(6))
                            // data: [DONE] 这种是结束标记，但也可能只是空行
                            if jsonStr == "[DONE]" { break }
                            
                            if let data = jsonStr.data(using: .utf8),
                               let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let candidates = jsonObject["candidates"] as? [[String: Any]],
                               let content = candidates.first?["content"] as? [String: Any],
                               let parts = content["parts"] as? [[String: Any]],
                               let text = parts.first?["text"] as? String {
                                
                                // 将解析到的文本片段发送出去
                                continuation.yield(text)
                            }
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
