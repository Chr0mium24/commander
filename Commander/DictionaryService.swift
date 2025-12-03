//
//  DictionaryService.swift
//  Commander
//
//  Created by Chr0mium on 11/22/25.
//

import Foundation
import CoreServices

struct DictionaryService {
    
    // 定义返回结果的类型，方便 AppState 知道最终是 AI 还是 Local
    enum LookupResult {
        case aiSuccess(fullText: String)
        case localSuccess(fullText: String)
        case failure(error: String)
    }

    // --- 核心业务逻辑：智能查词 (AI -> 失败转 Local) ---
    /// - Parameters:
    ///   - word: 查询单词
    ///   - apiKey: Gemini Key
    ///   - model: 模型名称
    ///   - onStream: 流式回调，用于实时更新 UI
    /// - Returns: 最终的查找结果元组
    static func performSmartLookup(
        word: String,
        apiKey: String,
        model: String,
        onStream: @MainActor @escaping (String) -> Void
    ) async -> LookupResult {
        
        let prompt = generateSmartPrompt(for: word)
        var fullResponse = ""
        
        do {
            // 尝试 AI 搜索
            for try await chunk in GeminiService.streamResponse(query: prompt, apiKey: apiKey, model: model) {
                fullResponse += chunk
                 onStream(chunk) // 回调给 UI 更新
            }
            return .aiSuccess(fullText: fullResponse)
            
        } catch {
            // AI 失败 (网络/Key错误)，回退到本地词典
            // 先通知 UI 发生错误并正在切换
            let errorMsg = "⚠️ Network unavailable. Using local dictionary...\n\n"
             onStream(errorMsg)
            
            // 查找本地
            if let localResult = formatLocalDefinition(word: word) {
                // 将本地结果拼接到错误提示后
                 onStream(localResult)
                return .localSuccess(fullText: errorMsg + localResult)
            } else {
                let notFoundMsg = "No definition found in local dictionary."
                 onStream(notFoundMsg)
                return .failure(error: notFoundMsg)
            }
        }
    }
    
    // --- 辅助：格式化本地词典结果 ---
    static func formatLocalDefinition(word: String) -> String? {
        guard let rawRes = lookupLocal(word: word) else { return nil }
        return """
        ###  Local Dictionary: **\(word)**
        
        > \(rawRes.replacingOccurrences(of: "\n", with: "\n> "))
        """
    }

    // ---原有基础功能保持不变---
    static func lookupLocal(word: String) -> String? {
        let range = DCSGetTermRangeInString(nil, word as CFString, 0)
        if let definition = DCSCopyTextDefinition(nil, word as CFString, range) {
            return String(definition.takeRetainedValue())
        }
        return nil
    }
    
    static func generateSmartPrompt(for word: String) -> String {
        return """
        You are a professional dictionary engine. Explain the word: "\(word)".
        
        **Format Requirements:**
        1. **Headword**: The word followed by IPA pronunciation.
        2. **🇨🇳 Chinese Definition**: Accurate Simplified Chinese translation. Don't use pinyin.
        3. **Etymology**: Show the etymology of words in Chinese.
        3. **🇬🇧 English Definition**: Concise, Oxford/Webster style definition.
        4. **Examples**: 2 useful example sentences showing usage.
        5. **Etymology/Tags** (Optional): E.g., [Noun], [Verb], or origin if interesting.
        
        **Style**:
        - Use Markdown.
        - Use `###` for headers.
        - Use **bold** for keywords.
        - Do not add conversational filler. Just the content.
        """
    }
}
