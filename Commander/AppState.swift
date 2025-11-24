import SwiftUI
import KeyboardShortcuts
import CoreServices
import AppKit

extension KeyboardShortcuts.Name {
    static let toggleWindow = Self("toggleWindow", default: .init(.space, modifiers: [.option]))
}

@Observable
class AppState {
    // --- UI State ---
    var isWindowPresented: Bool = false
    var query: String = ""
    var resultText: String = ""
    var isLoading: Bool = false
    var showHistoryView: Bool = false
    
    // 用于标记当前结果是否是 AI 生成的，以便展示特定按钮
    var isAIResponse: Bool = false
    var shouldOpenSettings: Bool = false
    
    // --- Data ---
    var history: [HistoryItem] = []
    
    init() {
        KeyboardShortcuts.onKeyUp(for: .toggleWindow) { [weak self] in
            self?.toggleWindow()
        }
        loadHistory()
    }
    
    func toggleWindow() {
        isWindowPresented.toggle()
        if isWindowPresented {
            NSApp.activate(ignoringOtherApps: true)
            showHistoryView = false
        }
    }
    
    func reset() {
        if !query.isEmpty {
            query = ""
        } else {
            resultText = ""
            isAIResponse = false
            showHistoryView = false
        }
    }

    // --- 核心指令执行 ---
    func executeCommand() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // 重置 UI 状态
        isAIResponse = false
        showHistoryView = false
        
        // 1. 解析指令
        // 将输入按空格分割，主要用于判断是否是保留命令
        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let firstWord = parts[0].lowercased()
        let content = parts.count > 1 ? parts[1] : ""
        
        // 获取设置中的 Python 别名
        let pyAlias = UserDefaults.standard.string(forKey: AppStorageKey.aliasPy) ?? "py"
        
        isLoading = true
        
        Task {
            // --- 保留命令优先处理 ---
            if firstWord == "quit" {
                quitApp()
            } else if firstWord == "history" {
                await MainActor.run {
                    self.showHistoryView = true
                    self.isLoading = false
                }
            } else if firstWord == "help" {
                showHelp()
            } else if firstWord == "set" {
                await MainActor.run {
                    self.triggerOpenSettings()
                }
            } else if firstWord == pyAlias {
                // 如果是 py 命令，执行脚本
                await runPythonScript(code: content)
            }
            // --- 智能判断逻辑 (AI 优先) ---
            else {
                // 判断是否包含中文
                let hasChinese = trimmed.range(of: "\\p{Han}", options: .regularExpression) != nil

                // 判断是否为单词：(不包含空格) 且 (不包含中文)
                let isSingleWord = !trimmed.contains(" ") && !hasChinese
                
                if isSingleWord {
                    // 逻辑：单次 -> 智能查词 (AI -> 失败转 Loc)
                    // 注意：performSmartDictionaryLookup 内部已包含 catch 错误后调用 performLocalDictionaryLookup 的逻辑
                    await performSmartDictionaryLookup(word: trimmed)
                } else {
                    // 逻辑：句子 -> 自动 AI 搜索
                    await performAIQuery(question: trimmed)
                }
            }
        }
    }
    
    // --- 具体功能实现 ---
    
    @MainActor
    private func performLocalDictionaryLookup(word: String) {
        if let rawRes = DictionaryService.lookupLocal(word: word) {
            let formattedRes = """
            ###  Local Dictionary: **\(word)**
            
            > \(rawRes.replacingOccurrences(of: "\n", with: "\n> "))
            """
            self.resultText = formattedRes
            // 记录类型标记为 'loc'
            finalizeCommand(type: "loc", input: word, output: formattedRes)
        } else {
            self.resultText = "No definition found in local dictionary."
            self.isLoading = false
        }
    }
    
    @MainActor
    private func performSmartDictionaryLookup(word: String) async {
        self.resultText = ""
        let key = UserDefaults.standard.string(forKey: AppStorageKey.geminiKey) ?? ""
        let model = UserDefaults.standard.string(forKey: AppStorageKey.geminiModel) ?? "gemini-1.5-flash"
        
        let prompt = DictionaryService.generateSmartPrompt(for: word)
        
        var fullResponse = ""
        
        do {
            for try await chunk in GeminiService.streamResponse(query: prompt, apiKey: key, model: model) {
                self.resultText += chunk
                fullResponse += chunk
            }
            
            self.isAIResponse = true
            // 记录类型标记为 'AI-Def' 或 'Auto'
            finalizeCommand(type: "def", input: word, output: fullResponse)
            
        } catch {
            // 连不到网或 API 错误，回退到本地词典
            self.resultText = "⚠️ Network unavailable. Using local dictionary...\n\n"
            performLocalDictionaryLookup(word: word)
        }
    }

    @MainActor
    private func triggerOpenSettings() {
        self.isWindowPresented = false
        self.query = ""
        self.isLoading = false
        self.shouldOpenSettings = true
    }
    
    @MainActor
    private func runPythonScript(code: String) async {
        self.resultText = "Running Python script..."
        let result = await PythonRunner.run(code: code)
        
        let formattedOutput = """
        ### 🐍 Python Output
        ```text
        \(result)
        ```
        """
        self.resultText = formattedOutput
        finalizeCommand(type: "py", input: code, output: result)
    }

    @MainActor
    private func performAIQuery(question: String) async {
        self.resultText = ""
        let key = UserDefaults.standard.string(forKey: AppStorageKey.geminiKey) ?? ""
        let model = UserDefaults.standard.string(forKey: AppStorageKey.geminiModel) ?? "gemini-1.5-flash"
        
        var fullResponse = ""
        
        do {
            for try await chunk in GeminiService.streamResponse(query: question, apiKey: key, model: model) {
                self.resultText += chunk
                fullResponse += chunk
            }
            
            self.isAIResponse = true
            // 记录类型标记为 'AI'
            finalizeCommand(type: "ai", input: question, output: fullResponse)
            
        } catch {
            self.resultText = "Error: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
    
    // Web Search 被移除自动触发，若需要可作为备选，或者在 AI 回答中引导
    // 这里保留方法以防未来通过特定指令调用，但 executeCommand 中不再默认调用
    private func performWebSearch(term: String) {
        let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
            NSWorkspace.shared.open(url)
            DispatchQueue.main.async {
                self.isWindowPresented = false
                self.query = ""
                self.isLoading = false
            }
            saveHistoryItem(type: "ser", input: term, output: "Opened Web Search")
        }
    }
    
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @MainActor
    private func showHelp() {
        let py = UserDefaults.standard.string(forKey: AppStorageKey.aliasPy) ?? "py"
        
        let helpText = """
        ### 🚀 Commander AI Mode

        Simply type what you want to know.

        - **One Word**: Smart Dictionary Lookup (AI Definition -> Local Backup).
        - **Sentence**: AI Chat / Answer.
        
        #### Special Commands
        | Command | Description |
        | :--- | :--- |
        | `\(py) <code>` | Execute Python Code |
        | `history` | View Command History |
        | `set` | Open Settings |
        | `quit` | Quit Application |
        | `help` | Show this message |

        ---
        """
        self.resultText = helpText
        self.isLoading = false
    }
    
    @MainActor
    private func finalizeCommand(type: String, input: String, output: String) {
        self.isLoading = false
        
        if UserDefaults.standard.bool(forKey: AppStorageKey.autoCopy) {
            copyToClipboard(output)
        }
        
        saveHistoryItem(type: type, input: input, output: output)
    }
    
    private func saveHistoryItem(type: String, input: String, output: String) {
        let item = HistoryItem(type: type, query: input, result: output, timestamp: Date())
        history.insert(item, at: 0)
        let limit = UserDefaults.standard.integer(forKey: AppStorageKey.historyLimit)
        let actualLimit = limit > 0 ? limit : 10
        if history.count > actualLimit {
            history = Array(history.prefix(actualLimit))
        }
        persistHistory()
    }
    
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func historyFileURL() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("commander_history.json")
    }
    
    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyFileURL())
        }
    }
    
    private func loadHistory() {
        if let data = try? Data(contentsOf: historyFileURL()),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            self.history = decoded
        }
    }
    
    func deleteHistoryItem(id: UUID) {
        history.removeAll { $0.id == id }
        persistHistory()
    }
    
    func restoreHistoryItem(_ item: HistoryItem) {
        // 恢复时不再强制加前缀，直接放入 query
        // 除非是 py 命令，否则直接放原文即可触发对应逻辑
        if item.type == "py" {
             self.query = "py \(item.query)"
        } else {
             self.query = item.query
        }
        self.resultText = item.result
        self.showHistoryView = false
    }
}
