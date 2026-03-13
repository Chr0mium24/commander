import SwiftUI
import KeyboardShortcuts
import AppKit
import CoreServices

extension KeyboardShortcuts.Name {
    static let toggleWindow = Self("toggleWindow", default: .init(.space, modifiers: [.option]))
}

@Observable
class AppState {
    var isWindowPresented: Bool = false
    var query: String = ""
    var resultText: String = ""
    var isLoading: Bool = false
    var showHistoryView: Bool = false

    var isAIResponse: Bool = false
    var shouldOpenSettings: Bool = false

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

    func executeCommand() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isAIResponse = false
        showHistoryView = false
        isLoading = true
        resultText = ""

        Task {
            let response = await PythonCommandService.execute(
                query: trimmed,
                settings: CommandEngineSettings.current()
            )

            await MainActor.run {
                self.applyCommandResponse(response, originalQuery: trimmed)
            }
        }
    }

    @MainActor
    private func applyCommandResponse(_ response: CommandEngineResponse, originalQuery: String) {
        applySettingUpdates(response.settingUpdates)

        if let openURL = response.openURL, let url = URL(string: openURL) {
            NSWorkspace.shared.open(url)
        }

        if response.shouldQuit {
            quitApp()
            return
        }

        if response.openSettings {
            triggerOpenSettings()
            return
        }

        if response.showHistory {
            resultText = ""
            showHistoryView = true
            isLoading = false
            return
        }

        if response.deferAI {
            let type = response.historyType.isEmpty ? "ai" : response.historyType
            let input = response.historyInput.isEmpty ? originalQuery : response.historyInput
            streamAIResponse(prompt: response.aiPrompt, historyType: type, historyInput: input)
            return
        }

        resultText = response.output
        isAIResponse = response.isAIResponse

        if response.shouldSaveHistory {
            let type = response.historyType.isEmpty ? "cmd" : response.historyType
            let input = response.historyInput.isEmpty ? originalQuery : response.historyInput
            finalizeCommand(type: type, input: input, output: response.output)
            return
        }

        if UserDefaults.standard.bool(forKey: AppStorageKey.autoCopy), !response.output.isEmpty {
            copyToClipboard(response.output)
        }

        isLoading = false
    }

    private func streamAIResponse(prompt: String, historyType: String, historyInput: String) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resultText = "Error: Missing AI prompt."
            isLoading = false
            return
        }

        let apiKey = UserDefaults.standard.string(forKey: AppStorageKey.geminiKey) ?? ""
        let model = UserDefaults.standard.string(forKey: AppStorageKey.geminiModel) ?? "gemini-1.5-flash"
        let proxy = UserDefaults.standard.string(forKey: AppStorageKey.geminiProxy) ?? ""

        resultText = "Thinking..."

        Task {
            var fullResponse = ""

            do {
                for try await chunk in GeminiStreamingService.streamResponse(
                    prompt: prompt,
                    apiKey: apiKey,
                    model: model,
                    proxyURL: proxy
                ) {
                    fullResponse += chunk

                    await MainActor.run {
                        if self.resultText == "Thinking..." {
                            self.resultText = chunk
                        } else {
                            self.resultText += chunk
                        }
                    }
                }

                await MainActor.run {
                    self.isAIResponse = true
                    let output = fullResponse.isEmpty ? "Done (No Output)" : fullResponse
                    self.finalizeCommand(type: historyType, input: historyInput, output: output)
                }
            } catch {
                await MainActor.run {
                    if historyType == "def",
                       let word = self.extractDictionaryWord(from: historyInput),
                       let local = self.localDictionaryMarkdown(word: word) {
                        self.isAIResponse = false
                        self.finalizeCommand(type: "loc", input: historyInput, output: local)
                        return
                    }

                    self.isAIResponse = false
                    self.resultText = "Error: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func extractDictionaryWord(from historyInput: String) -> String? {
        let trimmed = historyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !trimmed.contains(" ") {
            return trimmed
        }

        let alias = (UserDefaults.standard.string(forKey: AppStorageKey.aliasDef) ?? "def").lowercased()
        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        if parts[0].lowercased() == alias {
            return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func localDictionaryMarkdown(word: String) -> String? {
        let range = DCSGetTermRangeInString(nil, word as CFString, 0)
        guard let definition = DCSCopyTextDefinition(nil, word as CFString, range) else {
            return nil
        }

        let text = String(definition.takeRetainedValue())
        return """
        ### Local Dictionary: **\(word)**

        > \(text.replacingOccurrences(of: "\n", with: "\n> "))
        """
    }

    @MainActor
    private func triggerOpenSettings() {
        isWindowPresented = false
        query = ""
        isLoading = false
        shouldOpenSettings = true
    }

    private func applySettingUpdates(_ updates: [CommandEngineSettingUpdate]) {
        guard !updates.isEmpty else { return }

        for update in updates {
            switch update.valueType.lowercased() {
            case "int":
                if let intValue = Int(update.value) {
                    UserDefaults.standard.set(intValue, forKey: update.key)
                }
            case "bool":
                let lowered = update.value.lowercased()
                let boolValue = lowered == "1" || lowered == "true" || lowered == "yes" || lowered == "on"
                UserDefaults.standard.set(boolValue, forKey: update.key)
            default:
                UserDefaults.standard.set(update.value, forKey: update.key)
            }
        }
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @MainActor
    func openWindowFromMenu() {
        isWindowPresented = true
        NSApp.activate(ignoringOtherApps: true)
        showHistoryView = false
    }

    @MainActor
    func openSettingsFromMenu() {
        isWindowPresented = false
        query = ""
        isLoading = false
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func quitFromMenu() {
        quitApp()
    }

    @MainActor
    private func finalizeCommand(type: String, input: String, output: String) {
        isLoading = false

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
            history = decoded
        }
    }

    func deleteHistoryItem(id: UUID) {
        history.removeAll { $0.id == id }
        persistHistory()
    }

    func restoreHistoryItem(_ item: HistoryItem) {
        query = item.query
        resultText = item.result
        showHistoryView = false
    }
}
