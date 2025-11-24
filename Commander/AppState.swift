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
    var resultText: String = "" // 1. 修改: 默认不显示 "Ready..."，改为空
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
            // 注意：打开窗口时是否要清空上次的内容？
            // 如果希望每次打开都像新的一样，可以取消下面这行的注释：
            // reset()
        }
    }
    
    // 2. 新增: ESC 键重置状态逻辑
    func reset() {
        if !query.isEmpty {
            query = "" // 如果有输入，先清空输入
        } else {
            // 如果输入已空，清空结果回到初始状态
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
        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let command = parts[0].lowercased()
        let content = parts.count > 1 ? parts[1] : ""
        
        let defAlias = UserDefaults.standard.string(forKey: AppStorageKey.aliasDef) ?? "def"
        let askAlias = UserDefaults.standard.string(forKey: AppStorageKey.aliasAsk) ?? "ask"
        let serAlias = UserDefaults.standard.string(forKey: AppStorageKey.aliasSer) ?? "ser"
        let pyAlias = UserDefaults.standard.string(forKey: AppStorageKey.aliasPy) ?? "py"
        
        isLoading = true
        
        Task {
            if command == "quit" {
                quitApp()
            } else if command == "history" {
                await MainActor.run {
                    self.showHistoryView = true
                    self.isLoading = false
                }
            } else if command == "help" {
                showHelp()
            } else if command == "set" {
                await MainActor.run {
                    self.triggerOpenSettings()
                }
            } else if command == "loc" {
                performLocalDictionaryLookup(word: content)
            } else if command == defAlias {
                await performSmartDictionaryLookup(word: content)
            } else if command == askAlias {
                await performAIQuery(question: content)
            } else if command == serAlias {
                performWebSearch(term: content)
            } else if command == pyAlias {
                await runPythonScript(code: content)
            } else {
                 await MainActor.run {
                     self.resultText = "Unknown command. Type 'help' to see commands."
                     self.isLoading = false
                 }
            }
        }
    }
    
    // --- 具体功能实现 ---
    
    @MainActor
        private func performLocalDictionaryLookup(word: String) {
            // 调用 DictionaryService
            if let rawRes = DictionaryService.lookupLocal(word: word) {
                let formattedRes = """
                ###  Local Dictionary: **\(word)**
                
                > \(rawRes.replacingOccurrences(of: "\n", with: "\n> "))
                """
                self.resultText = formattedRes
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
            
            // 从 Service 获取 Prompt
            let prompt = DictionaryService.generateSmartPrompt(for: word)
            
            var fullResponse = ""
            
            do {
                for try await chunk in GeminiService.streamResponse(query: prompt, apiKey: key, model: model) {
                    self.resultText += chunk
                    fullResponse += chunk
                }
                
                self.isAIResponse = true
                finalizeCommand(type: "def", input: word, output: fullResponse)
                
            } catch {
                // AI 失败回退到本地逻辑
                self.resultText = "⚠️ Network error. Falling back to local dictionary...\n\n"
                performLocalDictionaryLookup(word: word)
            }
        }

    
    @MainActor
    private func triggerOpenSettings() {
            // 关闭当前命令窗口
            self.isWindowPresented = false
            self.query = ""
            self.isLoading = false
            
            // 设置信号为 true，通知 ContentView 执行动作
            self.shouldOpenSettings = true
        }
    
    @MainActor
        private func runPythonScript(code: String) async {
            self.resultText = "Running Python script..."
            
            // 调用 PythonRunner Service
            let result = await PythonRunner.run(code: code)
            
            // UI 格式化封装
            let formattedOutput = """
            ### 🐍 Python Output
            ```text
            \(result)
            ```
            """
            self.resultText = formattedOutput
            
            // 存入历史记录 (raw code -> raw output)
            finalizeCommand(type: "py", input: code, output: result)
        }

    
    @MainActor
        private func performAIQuery(question: String) async {
            // 初始状态
            self.resultText = "" // 先清空，准备接收流
            let key = UserDefaults.standard.string(forKey: AppStorageKey.geminiKey) ?? ""
            let model = UserDefaults.standard.string(forKey: AppStorageKey.geminiModel) ?? "gemini-1.5-flash"
            
            // 临时变量用于拼接完整结果以便存入历史记录
            var fullResponse = ""
            
            do {
                // 使用流式请求
                for try await chunk in GeminiService.streamResponse(query: question, apiKey: key, model: model) {
                    // 一旦收到第一个字符，就可以把 loading 状态去掉(或者保留直到结束，看个人喜好，这里选择保留直到结束)
                    // self.isLoading = false
                    
                    self.resultText += chunk
                    fullResponse += chunk
                }
                
                // 流结束
                self.isAIResponse = true
                finalizeCommand(type: "ask", input: question, output: fullResponse)
                
            } catch {
                self.resultText = "Error: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    
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
        // ... (保持原有逻辑)
        let def = UserDefaults.standard.string(forKey: AppStorageKey.aliasDef) ?? "def"
        let ask = UserDefaults.standard.string(forKey: AppStorageKey.aliasAsk) ?? "ask"
        let ser = UserDefaults.standard.string(forKey: AppStorageKey.aliasSer) ?? "ser"
        let py = UserDefaults.standard.string(forKey: AppStorageKey.aliasPy) ?? "py"
        
        let helpText = """
        ### Available Commands

        These commands allow interaction with various services. Command prefixes (e.g., `\(def)`) are defined by constants in the application environment.

        | Command Syntax | Description |
        | :--- | :--- |
        | `\(def) <word>` | Local Dictionary Lookup |
        | `\(ask) <query>` | AI Chat (Gemini) |
        | `\(ser) <term>` | Google Search |
        | `\(py) <code>` | Execute Python Code |
        | `history` | View Request History |
        | `set` | Open Settings |
        | `quit` | Quit Application |
        | `help` | Show this message |

        ---

        #### Input Controls
        *   **`ESC`**: Clear / Reset the current input buffer.
        """

        
        
        
        self.resultText = helpText
        self.isLoading = false
    }
    
    // --- 辅助逻辑 ---
    
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
    
    // ... (保持 History Persistence 和 UI Actions 逻辑不变)
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
        self.query = "\(item.type) \(item.query)"
        self.resultText = item.result
        self.showHistoryView = false
    }
}



