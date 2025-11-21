import Foundation
import CoreServices // 必须引入，用于 DCS 函数

struct DictionaryService {
    
    /// 查找 macOS 本地词典
    /// - Parameter word: 单词
    /// - Returns: 定义内容（如果有）
    static func lookupLocal(word: String) -> String? {
        let range = DCSGetTermRangeInString(nil, word as CFString, 0)
        // 如果 range.location == kCFNotFound，说明没找到，DCSCopyTextDefinition 可能返回 nil
        if let definition = DCSCopyTextDefinition(nil, word as CFString, range) {
            return String(definition.takeRetainedValue())
        }
        return nil
    }
    
    /// 生成用于 AI 智能词典的 Prompt
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