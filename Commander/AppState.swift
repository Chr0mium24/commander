import SwiftUI
import KeyboardShortcuts
import AppKit
import CoreServices

extension KeyboardShortcuts.Name {
    static let toggleWindow = Self("toggleWindow", default: .init(.space, modifiers: [.option]))
}

struct TerminalSessionItem: Identifiable, Equatable {
    let id: UUID
    let command: String
    let historyType: String
    let historyInput: String
    var outputData: Data
    var isRunning: Bool
    var runInBackground: Bool
    var isCollapsed: Bool
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
    var windowToggleHandler: (() -> Void)?
    var windowShowHandler: (() -> Void)?
    var windowHideHandler: (() -> Void)?

    var terminalSessions: [TerminalSessionItem] = []

    var history: [HistoryItem] = []

    private var activeExecutionID: UUID = UUID()
    private var activeCommandTask: Task<Void, Never>?
    private var shellSessions: [UUID: ShellSession] = [:]
    private var terminalTerminators: [UUID: () -> Void] = [:]
    private var terminalStopFallbackTasks: [UUID: Task<Void, Never>] = [:]
    private var interruptedTerminalSessions: Set<UUID> = []
    private var lastSubmitAt: Date = .distantPast
    private var commandHistoryCursor: Int?

    private let minSubmitInterval: TimeInterval = 0.20
    private let routeTimeoutNanoseconds: UInt64 = 8_000_000_000

    init() {
        KeyboardShortcuts.onKeyUp(for: .toggleWindow) { [weak self] in
            self?.toggleWindow()
        }
        loadHistory()
    }

    func toggleWindow() {
        if let windowToggleHandler {
            windowToggleHandler()
            return
        }
        isWindowPresented.toggle()
        if isWindowPresented {
            NSApp.activate(ignoringOtherApps: true)
            showHistoryView = false
        }
    }

    func reset() {
        commandHistoryCursor = nil
        if !query.isEmpty {
            query = ""
        } else {
            resultText = ""
            isAIResponse = false
            showHistoryView = false
            terminateAllShellSessions()
            terminalSessions = []
        }
    }

    func collapseToInputOnly() {
        commandHistoryCursor = nil
        query = ""
        resultText = ""
        isAIResponse = false
        showHistoryView = false
        isLoading = false
        terminateAllShellSessions()
        terminalSessions = []
    }

    func executeCommand(queryOverride: String? = nil) {
        let sourceQuery = queryOverride ?? query
        let trimmed = sourceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if queryOverride != nil {
            query = trimmed
        }
        
        let now = Date()
        guard now.timeIntervalSince(lastSubmitAt) >= minSubmitInterval else { return }
        lastSubmitAt = now
        commandHistoryCursor = nil

        cancelActiveExecution(showInterruptedNote: false)
        let executionID = beginExecution()

        isAIResponse = false
        showHistoryView = false
        isLoading = true
        resultText = ""

        activeCommandTask = Task {
            let response = await runRoutingWithTimeout(
                query: trimmed,
                settings: CommandEngineSettings.current(),
                timeoutNanoseconds: routeTimeoutNanoseconds
            )

            await MainActor.run {
                self.applyCommandResponse(response, originalQuery: trimmed, executionID: executionID)
            }
        }
    }

    private func runRoutingWithTimeout(
        query: String,
        settings: CommandEngineSettings,
        timeoutNanoseconds: UInt64
    ) async -> CommandEngineResponse {
        await withTaskGroup(of: CommandEngineResponse.self) { group in
            group.addTask {
                await PythonCommandService.execute(query: query, settings: settings)
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return await MainActor.run {
                    CommandEngineResponse.failure("Command routing timed out. Please try again.")
                }
            }

            let first = if let first = await group.next() {
                first
            } else {
                await MainActor.run {
                    CommandEngineResponse.failure("Command routing failed.")
                }
            }
            group.cancelAll()
            return first
        }
    }

    func stopCurrentTask() {
        if isLoading {
            cancelActiveExecution(showInterruptedNote: true)
            return
        }

        guard let sessionID = terminalSessions.last(where: { $0.isRunning })?.id else { return }
        stopTerminalSession(sessionID)
    }

    func toggleTerminalSessionCollapsed(_ sessionID: UUID) {
        updateSession(sessionID) { session in
            session.isCollapsed.toggle()
        }
    }

    func stopTerminalSession(_ sessionID: UUID) {
        scheduleTerminalStopFallback(for: sessionID)

        if let terminator = terminalTerminators[sessionID] {
            interruptedTerminalSessions.insert(sessionID)
            terminator()
            return
        }

        guard let shell = shellSessions[sessionID] else { return }
        interruptedTerminalSessions.insert(sessionID)
        shell.terminate()
    }

    func registerTerminalSessionController(sessionID: UUID, terminate: @escaping () -> Void) {
        terminalTerminators[sessionID] = terminate
    }

    func completeTerminalSession(sessionID: UUID, exitCode: Int32?, transcript: String) {
        finishTerminalSession(sessionID: sessionID, exitCode: exitCode, transcriptOverride: transcript)
    }

    private func beginExecution() -> UUID {
        let executionID = UUID()
        activeExecutionID = executionID
        return executionID
    }

    private func isCurrentExecution(_ executionID: UUID) -> Bool {
        activeExecutionID == executionID
    }

    private func cancelActiveExecution(showInterruptedNote: Bool) {
        activeExecutionID = UUID()

        activeCommandTask?.cancel()
        activeCommandTask = nil

        if showInterruptedNote {
            if isLoading {
                resultText = "Interrupted."
            }
        }

        isLoading = false
    }

    @MainActor
    private func applyCommandResponse(_ response: CommandEngineResponse, originalQuery: String, executionID: UUID) {
        guard isCurrentExecution(executionID) else { return }

        applySettingUpdates(response.settingUpdates)
        activeCommandTask = nil

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

        if response.deferShell {
            let type = response.historyType.isEmpty ? "run" : response.historyType
            let input = response.historyInput.isEmpty ? originalQuery : response.historyInput
            startShellSession(
                command: response.shellCommand,
                runInBackground: response.shellRunInBackground,
                historyType: type,
                historyInput: input
            )
            return
        }

        if response.deferAI {
            let type = response.historyType.isEmpty ? "ai" : response.historyType
            let input = response.historyInput.isEmpty ? originalQuery : response.historyInput
            streamAIResponse(
                prompt: response.aiPrompt,
                historyType: type,
                historyInput: input,
                executionID: executionID,
                aiRequest: response.aiRequest
            )
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

    private func streamAIResponse(
        prompt: String,
        historyType: String,
        historyInput: String,
        executionID: UUID,
        aiRequest: CommandEngineAIRequest
    ) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resultText = "Error: Missing AI prompt."
            isLoading = false
            return
        }

        resultText = "Thinking..."

        activeCommandTask = Task {
            var fullResponse = ""

            do {
                let resolvedRequest = try GeminiStreamingService.resolveRequest(
                    kind: aiRequest.kind,
                    provider: aiRequest.provider,
                    baseURL: aiRequest.baseURL,
                    apiKey: aiRequest.apiKey,
                    model: aiRequest.model,
                    proxyURL: aiRequest.proxyURL
                )

                for try await chunk in GeminiStreamingService.streamResponse(
                    prompt: prompt,
                    request: resolvedRequest
                ) {
                    if Task.isCancelled { return }
                    fullResponse += chunk

                    await MainActor.run {
                        guard self.isCurrentExecution(executionID) else { return }
                        if self.resultText == "Thinking..." {
                            self.resultText = chunk
                        } else {
                            self.resultText += chunk
                        }
                    }
                }

                await MainActor.run {
                    guard self.isCurrentExecution(executionID) else { return }
                    self.activeCommandTask = nil
                    self.isAIResponse = true
                    let output = fullResponse.isEmpty ? "Done (No Output)" : fullResponse
                    self.finalizeCommand(type: historyType, input: historyInput, output: output)
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard self.isCurrentExecution(executionID) else { return }
                    self.activeCommandTask = nil
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    guard self.isCurrentExecution(executionID) else { return }
                    self.activeCommandTask = nil

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

    private func startShellSession(
        command: String,
        runInBackground: Bool,
        historyType: String,
        historyInput: String
    ) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resultText = "Error: Empty shell command"
            isLoading = false
            return
        }

        let sessionID = UUID()
        let initialOutput = Data("$ \(trimmed)\n".utf8)
        terminalSessions.append(
            TerminalSessionItem(
                id: sessionID,
                command: trimmed,
                historyType: historyType,
                historyInput: historyInput,
                outputData: initialOutput,
                isRunning: true,
                runInBackground: runInBackground,
                isCollapsed: false
            )
        )
        showHistoryView = false
        isLoading = false

        guard runInBackground else {
            return
        }

        do {
            let shell = try ShellSession.start(
                command: trimmed,
                runInBackground: runInBackground,
                onOutput: { [weak self] chunk in
                    guard let self else { return }
                    self.updateSession(sessionID) { session in
                        session.outputData.append(chunk)
                    }
                },
                onExit: { [weak self] status in
                    guard let self else { return }
                    self.finishTerminalSession(sessionID: sessionID, exitCode: status, transcriptOverride: nil)
                }
            )
            shellSessions[sessionID] = shell
        } catch {
            updateSession(sessionID) { session in
                session.isRunning = false
                session.outputData.append(contentsOf: "\nFailed to start process: \(error.localizedDescription)\n".utf8)
            }
            isLoading = false
            let fallbackOutput = sessionByID(sessionID).map {
                String(decoding: $0.outputData, as: UTF8.self)
            } ?? "Failed to start process."
            finishTerminalSession(sessionID: sessionID, exitCode: nil, transcriptOverride: fallbackOutput)
        }
    }

    private func indexOfSession(id: UUID) -> Int? {
        terminalSessions.firstIndex(where: { $0.id == id })
    }

    private func sessionByID(_ sessionID: UUID) -> TerminalSessionItem? {
        guard let index = indexOfSession(id: sessionID) else { return nil }
        return terminalSessions[index]
    }

    private func updateSession(_ sessionID: UUID, mutate: (inout TerminalSessionItem) -> Void) {
        guard let index = indexOfSession(id: sessionID) else { return }
        var session = terminalSessions[index]
        mutate(&session)
        terminalSessions[index] = session
    }

    private func terminateAllShellSessions() {
        for task in terminalStopFallbackTasks.values {
            task.cancel()
        }
        terminalStopFallbackTasks.removeAll()

        for shell in shellSessions.values {
            shell.terminate()
        }
        for terminate in terminalTerminators.values {
            terminate()
        }
        shellSessions.removeAll()
        terminalTerminators.removeAll()
        interruptedTerminalSessions.removeAll()
    }

    private func finishTerminalSession(sessionID: UUID, exitCode: Int32?, transcriptOverride: String?) {
        guard let session = sessionByID(sessionID) else { return }

        terminalStopFallbackTasks[sessionID]?.cancel()
        terminalStopFallbackTasks[sessionID] = nil

        shellSessions[sessionID] = nil
        terminalTerminators[sessionID] = nil

        let interrupted = interruptedTerminalSessions.remove(sessionID) != nil
        var output = (transcriptOverride ?? String(decoding: session.outputData, as: UTF8.self))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if interrupted {
            if output.isEmpty {
                output = "[Interrupted]"
            } else if !output.contains("[Interrupted]") {
                output += "\n[Interrupted]"
            }
        } else if let code = exitCode, code != 0 {
            if output.isEmpty {
                output = "[Process exited with code \(code)]"
            } else {
                output += "\n[Process exited with code \(code)]"
            }
        }

        if output.isEmpty {
            output = "Done (No Output)"
        }

        finalizeCommand(type: session.historyType, input: session.historyInput, output: output)
        terminalSessions.removeAll { $0.id == sessionID }
    }

    private func scheduleTerminalStopFallback(for sessionID: UUID) {
        terminalStopFallbackTasks[sessionID]?.cancel()

        terminalStopFallbackTasks[sessionID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                guard let self else { return }
                guard self.sessionByID(sessionID) != nil else { return }
                self.finishTerminalSession(
                    sessionID: sessionID,
                    exitCode: nil,
                    transcriptOverride: nil
                )
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
        windowHideHandler?()
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
        if let windowShowHandler {
            windowShowHandler()
            return
        }
        isWindowPresented = true
        NSApp.activate(ignoringOtherApps: true)
        showHistoryView = false
    }

    @MainActor
    func openSettingsFromMenu() {
        windowHideHandler?()
        isWindowPresented = false
        query = ""
        isLoading = false
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func quitFromMenu() {
        quitApp()
    }

    func restorePreviousCommandResult() {
        guard !isLoading else { return }
        guard !history.isEmpty else { return }

        let baseIndex = resolvedCommandHistoryBaseIndex(defaultValue: -1)
        let target = min(baseIndex + 1, history.count - 1)
        guard target >= 0, target < history.count else { return }
        guard target != baseIndex else { return }

        applyHistorySnapshot(history[target])
        commandHistoryCursor = target
    }

    func restoreNextCommandResult() {
        guard !isLoading else { return }
        guard !history.isEmpty else { return }

        let baseIndex = resolvedCommandHistoryBaseIndex(defaultValue: history.count)
        let target = max(baseIndex - 1, 0)
        guard target >= 0, target < history.count else { return }
        guard target != baseIndex else { return }

        applyHistorySnapshot(history[target])
        commandHistoryCursor = target
    }

    func clearCommandHistoryNavigation() {
        commandHistoryCursor = nil
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
        commandHistoryCursor = nil

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

    @MainActor
    func runGeneratedCode(language: String, code: String) {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return }

        guard let runCommand = buildRunCommandForGeneratedCode(language: language, code: trimmedCode) else {
            resultText = "Unsupported code language. Use python/bash/sh/zsh."
            isLoading = false
            return
        }

        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let historyInput = normalizedLanguage.isEmpty ? "run code" : "run \(normalizedLanguage) code"
        let pausedCommand = wrapCommandWithPause(runCommand)

        startShellSession(
            command: pausedCommand,
            runInBackground: false,
            historyType: "run",
            historyInput: historyInput
        )
    }

    private func buildRunCommandForGeneratedCode(language: String, code: String) -> String? {
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedLanguage: String

        if normalizedLanguage.isEmpty {
            if code.hasPrefix("#!/bin/bash") || code.hasPrefix("#!/usr/bin/env bash") {
                resolvedLanguage = "bash"
            } else if code.hasPrefix("#!/bin/zsh") || code.hasPrefix("#!/usr/bin/env zsh") {
                resolvedLanguage = "zsh"
            } else if code.hasPrefix("#!/usr/bin/python") || code.hasPrefix("#!/usr/bin/env python") {
                resolvedLanguage = "python"
            } else {
                return nil
            }
        } else {
            resolvedLanguage = normalizedLanguage
        }

        switch resolvedLanguage {
        case "python", "py":
            guard let fileURL = writeGeneratedScript(code: code, fileExtension: "py") else {
                return nil
            }
            let interpreter = UserDefaults.standard.string(forKey: AppStorageKey.pythonPath) ?? "/usr/bin/python3"
            return "\(shellQuote(interpreter)) \(shellQuote(fileURL.path))"

        case "bash", "sh", "shell":
            guard let fileURL = writeGeneratedScript(code: code, fileExtension: "sh") else {
                return nil
            }
            return "/bin/bash \(shellQuote(fileURL.path))"

        case "zsh":
            guard let fileURL = writeGeneratedScript(code: code, fileExtension: "sh") else {
                return nil
            }
            return "/bin/zsh \(shellQuote(fileURL.path))"

        default:
            return nil
        }
    }

    private func wrapCommandWithPause(_ command: String) -> String {
        """
        \(command)
        __commander_status=$?
        printf '\\n[Done] Press any key to close...'
        read -rsk 1 __commander_key
        printf '\\n'
        exit $__commander_status
        """
    }

    private func writeGeneratedScript(code: String, fileExtension: String) -> URL? {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("CommanderGenerated", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
            try code.write(to: fileURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: fileURL.path)

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3600) {
                try? fileManager.removeItem(at: fileURL)
            }

            return fileURL
        } catch {
            return nil
        }
    }

    private func shellQuote(_ input: String) -> String {
        "'" + input.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
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
        if let cursor = commandHistoryCursor {
            commandHistoryCursor = cursor < history.count ? cursor : nil
        }
        persistHistory()
    }

    func restoreHistoryItem(_ item: HistoryItem) {
        applyHistorySnapshot(item)
        commandHistoryCursor = history.firstIndex(of: item)
    }

    private func resolvedCommandHistoryBaseIndex(defaultValue: Int) -> Int {
        if let cursor = commandHistoryCursor {
            return cursor
        }

        if let matched = history.firstIndex(where: { $0.query == query && $0.result == resultText }) {
            return matched
        }

        return defaultValue
    }

    private func applyHistorySnapshot(_ item: HistoryItem) {
        query = item.query
        resultText = item.result
        isAIResponse = ["ai", "def", "loc"].contains(item.type.lowercased())
        showHistoryView = false
        isLoading = false
    }
}
