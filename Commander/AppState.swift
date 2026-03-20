import SwiftUI
import KeyboardShortcuts
import AppKit
import CoreServices

extension KeyboardShortcuts.Name {
    static let toggleWindow = Self("toggleWindow", default: .init(.space, modifiers: [.option]))
}

enum ProgressPresentation: String {
    case terminal
    case note
    case todo
    case code
    case image
    case file
}

struct TodoItem: Identifiable, Equatable {
    let id: UUID
    var text: String
    var isCompleted: Bool

    init(id: UUID = UUID(), text: String, isCompleted: Bool = false) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
    }
}

struct ProgressSessionItem: Identifiable, Equatable {
    let id: UUID
    let command: String
    let displayTitle: String
    let presentation: ProgressPresentation
    let historyType: String
    let historyInput: String
    var outputData: Data
    var noteText: String
    var todoItems: [TodoItem]
    var todoDraft: String
    var codeText: String
    var codeLanguage: String
    var previewPath: String
    var currentDirectory: String
    var isRunning: Bool
    var runInBackground: Bool
    var isCollapsed: Bool
    var isDetached: Bool
}

@MainActor
@Observable
class AppState {
    var isWindowPresented: Bool = false
    var query: String = ""
    var resultText: String = ""
    var streamingMarkdownSnapshot: String = ""
    var streamingMarkdownTail: String = ""
    var isStreamingMarkdownActive: Bool = false
    var isLoading: Bool = false
    var showHistoryView: Bool = false

    var isAIResponse: Bool = false
    var shouldOpenSettings: Bool = false
    var windowToggleHandler: (() -> Void)?
    var windowShowHandler: (() -> Void)?
    var windowHideHandler: (() -> Void)?
    var progressSessionOpenHandler: ((UUID) -> Void)?
    var progressSessionCloseHandler: ((UUID) -> Void)?

    var progressSessions: [ProgressSessionItem] = []

    var history: [HistoryItem] = []

    private var activeExecutionID: UUID = UUID()
    private var activeCommandTask: Task<Void, Never>?
    private var shellSessions: [UUID: ShellSession] = [:]
    private var progressTerminators: [UUID: () -> Void] = [:]
    private var progressStopFallbackTasks: [UUID: Task<Void, Never>] = [:]
    private var interruptedProgressSessions: Set<UUID> = []
    private var lastSubmitAt: Date = .distantPast
    private var commandHistoryCursor: Int?

    private let minSubmitInterval: TimeInterval = 0.20
    private let routeTimeoutNanoseconds: UInt64 = 8_000_000_000

    private var streamingMarkdownCommitInterval: Int {
        let value = UserDefaults.standard.integer(forKey: AppStorageKey.streamingMarkdownCommitInterval)
        return value > 0 ? value : 50
    }

    init() {
        UserDefaults.standard.register(defaults: [
            AppStorageKey.streamingMarkdownCommitInterval: 50,
        ])
        KeyboardShortcuts.onKeyUp(for: .toggleWindow) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleWindow()
            }
        }
        loadHistory()
    }

    @MainActor
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

    @MainActor
    func reset() {
        commandHistoryCursor = nil
        if !query.isEmpty {
            query = ""
        } else {
            resultText = ""
            resetStreamingMarkdownState()
            isAIResponse = false
            showHistoryView = false
        }
    }

    @MainActor
    func collapseToInputOnly() {
        commandHistoryCursor = nil
        query = ""
        resultText = ""
        resetStreamingMarkdownState()
        isAIResponse = false
        showHistoryView = false
        isLoading = false
    }

    @MainActor
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
        resetStreamingMarkdownState()

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

    @MainActor
    func stopCurrentTask() {
        if isLoading {
            cancelActiveExecution(showInterruptedNote: true)
            return
        }

        guard let sessionID = progressSessions.last(where: { $0.isRunning })?.id else { return }
        stopProgressSession(sessionID)
    }

    func toggleProgressSessionCollapsed(_ sessionID: UUID) {
        updateSession(sessionID) { session in
            session.isCollapsed.toggle()
        }
    }

    func stopProgressSession(_ sessionID: UUID) {
        scheduleProgressStopFallback(for: sessionID)

        if let terminator = progressTerminators[sessionID] {
            interruptedProgressSessions.insert(sessionID)
            terminator()
            return
        }

        guard let shell = shellSessions[sessionID] else { return }
        interruptedProgressSessions.insert(sessionID)
        shell.terminate()
    }

    func closeProgressSession(_ sessionID: UUID) {
        guard let session = sessionByID(sessionID) else { return }
        if session.isRunning {
            stopProgressSession(sessionID)
            return
        }
        progressSessions.removeAll { $0.id == sessionID }
        progressSessionCloseHandler?(sessionID)
    }

    func detachProgressSession(_ sessionID: UUID) {
        guard let session = sessionByID(sessionID), !session.isDetached else { return }
        updateSession(sessionID) { item in
            item.isDetached = true
        }
        progressSessionOpenHandler?(sessionID)
    }

    func attachProgressSession(_ sessionID: UUID) {
        guard let session = sessionByID(sessionID), session.isDetached else { return }
        updateSession(sessionID) { item in
            item.isDetached = false
        }
        progressSessionCloseHandler?(sessionID)
    }

    func restoreDetachedProgressSession(_ sessionID: UUID) {
        guard let session = sessionByID(sessionID), session.isDetached else { return }
        updateSession(sessionID) { item in
            item.isDetached = false
        }
    }

    func noteText(for sessionID: UUID) -> String {
        sessionByID(sessionID)?.noteText ?? ""
    }

    func progressSession(id sessionID: UUID) -> ProgressSessionItem? {
        sessionByID(sessionID)
    }

    func updateProgressNote(sessionID: UUID, text: String) {
        updateSession(sessionID) { session in
            session.noteText = text
        }
    }

    func codeEditorText(for sessionID: UUID) -> String {
        sessionByID(sessionID)?.codeText ?? ""
    }

    func codeEditorLanguage(for sessionID: UUID) -> String {
        sessionByID(sessionID)?.codeLanguage ?? ""
    }

    func codeEditorWorkingDirectory(for sessionID: UUID) -> String {
        sessionByID(sessionID)?.currentDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    func updateCodeEditorText(sessionID: UUID, text: String) {
        updateSession(sessionID) { session in
            session.codeText = text
        }
    }

    func todoItems(for sessionID: UUID) -> [TodoItem] {
        sessionByID(sessionID)?.todoItems ?? []
    }

    func todoDraft(for sessionID: UUID) -> String {
        sessionByID(sessionID)?.todoDraft ?? ""
    }

    func updateTodoDraft(sessionID: UUID, text: String) {
        updateSession(sessionID) { session in
            session.todoDraft = text
        }
    }

    func addTodoItem(sessionID: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateSession(sessionID) { session in
            session.todoItems.append(TodoItem(text: trimmed))
            session.todoDraft = ""
        }
    }

    func toggleTodoItem(sessionID: UUID, itemID: UUID) {
        updateSession(sessionID) { session in
            guard let index = session.todoItems.firstIndex(where: { $0.id == itemID }) else { return }
            session.todoItems[index].isCompleted.toggle()
        }
    }

    func updateTodoItemText(sessionID: UUID, itemID: UUID, text: String) {
        updateSession(sessionID) { session in
            guard let index = session.todoItems.firstIndex(where: { $0.id == itemID }) else { return }
            session.todoItems[index].text = text
        }
    }

    func removeTodoItem(sessionID: UUID, itemID: UUID) {
        updateSession(sessionID) { session in
            session.todoItems.removeAll { $0.id == itemID }
        }
    }

    func clearCompletedTodoItems(sessionID: UUID) {
        updateSession(sessionID) { session in
            session.todoItems.removeAll { $0.isCompleted }
        }
    }

    @MainActor
    func openCodeEditor(language: String, code: String) {
        guard let workspaceURL = makeGeneratedWorkspace() else {
            resultText = "Failed to create editor workspace."
            isLoading = false
            return
        }

        let normalizedLanguage = normalizeGeneratedCodeLanguage(language: language, code: code) ?? language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let titleLanguage = normalizedLanguage.isEmpty ? "Code" : normalizedLanguage.uppercased()
        let sessionID = UUID()
        progressSessions.append(
            ProgressSessionItem(
                id: sessionID,
                command: "",
                displayTitle: "\(titleLanguage) Editor",
                presentation: .code,
                historyType: "code",
                historyInput: normalizedLanguage.isEmpty ? "edit code" : "edit \(normalizedLanguage) code",
                outputData: Data(),
                noteText: "",
                todoItems: [],
                todoDraft: "",
                codeText: code,
                codeLanguage: normalizedLanguage,
                previewPath: "",
                currentDirectory: workspaceURL.path,
                isRunning: false,
                runInBackground: false,
                isCollapsed: false,
                isDetached: true
            )
        )
        showHistoryView = false
        progressSessionOpenHandler?(sessionID)
    }

    @MainActor
    func runCodeEditorSession(_ sessionID: UUID) {
        guard let session = sessionByID(sessionID) else { return }
        runGeneratedCode(
            language: session.codeLanguage,
            code: session.codeText,
            workingDirectory: session.currentDirectory,
            displayTitle: session.displayTitle,
            detachSession: true
        )
    }

    func registerProgressSessionController(sessionID: UUID, terminate: @escaping () -> Void) {
        progressTerminators[sessionID] = terminate
    }

    func completeProgressSession(sessionID: UUID, exitCode: Int32?, transcript: String) {
        Task { @MainActor in
            self.finishProgressSession(
                sessionID: sessionID,
                exitCode: exitCode,
                transcriptOverride: transcript
            )
        }
    }

    private func beginExecution() -> UUID {
        let executionID = UUID()
        activeExecutionID = executionID
        return executionID
    }

    private func isCurrentExecution(_ executionID: UUID) -> Bool {
        activeExecutionID == executionID
    }

    @MainActor
    private func cancelActiveExecution(showInterruptedNote: Bool) {
        activeExecutionID = UUID()

        activeCommandTask?.cancel()
        activeCommandTask = nil

        if showInterruptedNote {
            if isLoading {
                resultText = "Interrupted."
                resetStreamingMarkdownState()
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
            resetStreamingMarkdownState()
            showHistoryView = true
            isLoading = false
            return
        }

        if response.openPanel {
            let type = response.historyType.isEmpty ? "panel" : response.historyType
            let input = response.historyInput.isEmpty ? originalQuery : response.historyInput
            let presentation = ProgressPresentation(rawValue: response.panelPresentation) ?? .file

            if presentation == .todo {
                openTodoPanel(
                    title: response.panelTitle,
                    initialItemText: response.panelText,
                    historyType: type,
                    historyInput: input
                )
            } else {
                openProgressPanel(
                    title: response.panelTitle,
                    presentation: presentation,
                    noteText: response.panelText,
                    previewPath: response.panelPath,
                    historyType: type,
                    historyInput: input
                )
            }

            resultText = response.output
            resetStreamingMarkdownState()
            isAIResponse = false

            if response.shouldSaveHistory {
                let output = response.output.isEmpty ? "Opened panel." : response.output
                finalizeCommand(type: type, input: input, output: output)
                return
            }

            isLoading = false
            return
        }

        if response.deferShell {
            let type = response.historyType.isEmpty ? "run" : response.historyType
            let input = response.historyInput.isEmpty ? originalQuery : response.historyInput
            startProgressSession(
                command: response.shellCommand,
                displayTitle: response.progressTitle,
                presentation: ProgressPresentation(rawValue: response.progressPresentation) ?? .terminal,
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
        resetStreamingMarkdownState()
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

    @MainActor
    private func streamAIResponse(
        prompt: String,
        historyType: String,
        historyInput: String,
        executionID: UUID,
        aiRequest: CommandEngineAIRequest
    ) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resultText = "Error: Missing AI prompt."
            resetStreamingMarkdownState()
            isLoading = false
            return
        }

        resultText = "Thinking..."
        resetStreamingMarkdownState()
        isStreamingMarkdownActive = true

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
                    let currentResponse = fullResponse

                    await MainActor.run {
                        guard self.isCurrentExecution(executionID) else { return }
                        self.resultText = currentResponse
                        self.updateStreamingMarkdownState(with: currentResponse)
                    }
                }

                let finalOutput = fullResponse.isEmpty ? "Done (No Output)" : fullResponse
                await MainActor.run {
                    guard self.isCurrentExecution(executionID) else { return }
                    self.activeCommandTask = nil
                    self.resultText = finalOutput
                    self.resetStreamingMarkdownState()
                    self.isAIResponse = true
                    self.finalizeCommand(type: historyType, input: historyInput, output: finalOutput)
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard self.isCurrentExecution(executionID) else { return }
                    self.activeCommandTask = nil
                    self.resetStreamingMarkdownState()
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
                        self.resultText = local
                        self.resetStreamingMarkdownState()
                        self.finalizeCommand(type: "loc", input: historyInput, output: local)
                        return
                    }

                    self.isAIResponse = false
                    self.resultText = "Error: \(error.localizedDescription)"
                    self.resetStreamingMarkdownState()
                    self.isLoading = false
                }
            }
        }
    }

    @MainActor
    private func resetStreamingMarkdownState() {
        streamingMarkdownSnapshot = ""
        streamingMarkdownTail = ""
        isStreamingMarkdownActive = false
    }

    @MainActor
    private func updateStreamingMarkdownState(with fullText: String) {
        guard !fullText.isEmpty else {
            resetStreamingMarkdownState()
            return
        }

        isStreamingMarkdownActive = true

        if streamingMarkdownSnapshot.count > fullText.count {
            streamingMarkdownSnapshot = ""
        }

        let committedCount = streamingMarkdownSnapshot.count
        let totalCount = fullText.count

        if let safeBoundary = safeStreamingMarkdownBoundary(in: fullText) {
            let safeCount = fullText.distance(from: fullText.startIndex, to: safeBoundary)
            if safeCount > committedCount {
                let snapshotEndIndex = fullText.index(fullText.startIndex, offsetBy: committedCount)
                let newSegment = String(fullText[snapshotEndIndex..<safeBoundary])
                let shouldCommit = totalCount - committedCount >= streamingMarkdownCommitInterval
                    || containsCodeFenceMarker(in: newSegment)

                if shouldCommit {
                    streamingMarkdownSnapshot = String(fullText[..<safeBoundary])
                }
            }
        }

        let latestCommittedCount = streamingMarkdownSnapshot.count
        if latestCommittedCount == 0 {
            streamingMarkdownTail = fullText
            return
        }

        let startIndex = fullText.index(fullText.startIndex, offsetBy: latestCommittedCount)
        streamingMarkdownTail = String(fullText[startIndex...])
    }

    private func safeStreamingMarkdownBoundary(in text: String) -> String.Index? {
        guard !text.isEmpty else { return nil }

        var currentLineStart = text.startIndex
        var inCodeFence = false
        var lastSafeBoundary: String.Index?

        while currentLineStart < text.endIndex {
            let newlineIndex = text[currentLineStart...].firstIndex(of: "\n") ?? text.endIndex
            let lineEnd = newlineIndex == text.endIndex ? text.endIndex : text.index(after: newlineIndex)
            let line = String(text[currentLineStart..<newlineIndex]).trimmingCharacters(in: .whitespaces)

            if isStreamingCodeFenceLine(line) {
                let wasInCodeFence = inCodeFence
                inCodeFence.toggle()
                if wasInCodeFence && !inCodeFence {
                    lastSafeBoundary = lineEnd
                }
            } else if !inCodeFence {
                lastSafeBoundary = lineEnd
            }

            currentLineStart = lineEnd
        }

        if !inCodeFence {
            return text.endIndex
        }

        return lastSafeBoundary
    }

    private func isStreamingCodeFenceLine(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~")
    }

    private func containsCodeFenceMarker(in text: String) -> Bool {
        text.contains("```") || text.contains("~~~")
    }

    @MainActor
    private func startProgressSession(
        command: String,
        displayTitle: String,
        presentation: ProgressPresentation,
        runInBackground: Bool,
        historyType: String,
        historyInput: String,
        currentDirectory: String? = nil,
        detached: Bool = false
    ) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resultText = "Error: Empty shell command"
            isLoading = false
            return
        }

        let sessionID = UUID()
        let initialOutput = Data("$ \(trimmed)\n".utf8)
        let resolvedTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? historyInput
            : displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDirectory = currentDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? currentDirectory!.trimmingCharacters(in: .whitespacesAndNewlines)
            : FileManager.default.homeDirectoryForCurrentUser.path

        progressSessions.append(
            ProgressSessionItem(
                id: sessionID,
                command: trimmed,
                displayTitle: resolvedTitle,
                presentation: presentation,
                historyType: historyType,
                historyInput: historyInput,
                outputData: initialOutput,
                noteText: "",
                todoItems: [],
                todoDraft: "",
                codeText: "",
                codeLanguage: "",
                previewPath: "",
                currentDirectory: resolvedDirectory,
                isRunning: true,
                runInBackground: runInBackground,
                isCollapsed: false,
                isDetached: detached
            )
        )
        if detached {
            progressSessionOpenHandler?(sessionID)
        }
        showHistoryView = false
        isLoading = false

        guard runInBackground else {
            return
        }

        do {
            let shell = try ShellSession.start(
                command: trimmed,
                runInBackground: runInBackground,
                currentDirectory: resolvedDirectory,
                onOutput: { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.updateSession(sessionID) { session in
                            session.outputData.append(chunk)
                        }
                    }
                },
                onExit: { [weak self] status in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.finishProgressSession(sessionID: sessionID, exitCode: status, transcriptOverride: nil)
                    }
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
            finishProgressSession(sessionID: sessionID, exitCode: nil, transcriptOverride: fallbackOutput)
        }
    }

    @MainActor
    private func openProgressPanel(
        title: String,
        presentation: ProgressPresentation,
        noteText: String,
        previewPath: String,
        historyType: String,
        historyInput: String
    ) {
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? historyInput
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        let sessionID = UUID()
        progressSessions.append(
            ProgressSessionItem(
                id: sessionID,
                command: "",
                displayTitle: resolvedTitle,
                presentation: presentation,
                historyType: historyType,
                historyInput: historyInput,
                outputData: Data(),
                noteText: noteText,
                todoItems: [],
                todoDraft: "",
                codeText: "",
                codeLanguage: "",
                previewPath: previewPath,
                currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
                isRunning: false,
                runInBackground: false,
                isCollapsed: false,
                isDetached: false
            )
        )
        showHistoryView = false
    }

    @MainActor
    private func openTodoPanel(
        title: String,
        initialItemText: String,
        historyType: String,
        historyInput: String
    ) {
        let trimmedItem = initialItemText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let sessionID = primaryTodoSessionID() {
            if !trimmedItem.isEmpty {
                addTodoItem(sessionID: sessionID, text: trimmedItem)
            }

            showHistoryView = false

            if let session = sessionByID(sessionID), session.isDetached {
                progressSessionOpenHandler?(sessionID)
            }
            return
        }

        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Todo"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        let initialItems = trimmedItem.isEmpty ? [] : [TodoItem(text: trimmedItem)]
        let sessionID = UUID()
        progressSessions.append(
            ProgressSessionItem(
                id: sessionID,
                command: "",
                displayTitle: resolvedTitle,
                presentation: .todo,
                historyType: historyType,
                historyInput: historyInput,
                outputData: Data(),
                noteText: "",
                todoItems: initialItems,
                todoDraft: "",
                codeText: "",
                codeLanguage: "",
                previewPath: "",
                currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
                isRunning: false,
                runInBackground: false,
                isCollapsed: false,
                isDetached: false
            )
        )
        showHistoryView = false
    }

    private func indexOfSession(id: UUID) -> Int? {
        progressSessions.firstIndex(where: { $0.id == id })
    }

    private func primaryTodoSessionID() -> UUID? {
        progressSessions.first(where: { $0.presentation == .todo })?.id
    }

    private func sessionByID(_ sessionID: UUID) -> ProgressSessionItem? {
        guard let index = indexOfSession(id: sessionID) else { return nil }
        return progressSessions[index]
    }

    private func updateSession(_ sessionID: UUID, mutate: (inout ProgressSessionItem) -> Void) {
        guard let index = indexOfSession(id: sessionID) else { return }
        var session = progressSessions[index]
        mutate(&session)
        progressSessions[index] = session
    }

    private func terminateAllShellSessions() {
        for task in progressStopFallbackTasks.values {
            task.cancel()
        }
        progressStopFallbackTasks.removeAll()

        for shell in shellSessions.values {
            shell.terminate()
        }
        for terminate in progressTerminators.values {
            terminate()
        }
        shellSessions.removeAll()
        progressTerminators.removeAll()
        interruptedProgressSessions.removeAll()
    }

    @MainActor
    private func finishProgressSession(sessionID: UUID, exitCode: Int32?, transcriptOverride: String?) {
        guard let session = sessionByID(sessionID) else { return }

        progressStopFallbackTasks[sessionID]?.cancel()
        progressStopFallbackTasks[sessionID] = nil

        shellSessions[sessionID] = nil
        progressTerminators[sessionID] = nil

        let interrupted = interruptedProgressSessions.remove(sessionID) != nil
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
        progressSessions.removeAll { $0.id == sessionID }
        progressSessionCloseHandler?(sessionID)
    }

    private func clearAllProgressSessions() {
        let sessionIDs = progressSessions.map(\.id)
        progressSessions.removeAll()
        for sessionID in sessionIDs {
            progressSessionCloseHandler?(sessionID)
        }
    }

    private func scheduleProgressStopFallback(for sessionID: UUID) {
        progressStopFallbackTasks[sessionID]?.cancel()

        progressStopFallbackTasks[sessionID] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self.finishProgressSession(
                sessionID: sessionID,
                exitCode: nil,
                transcriptOverride: nil
            )
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

    @MainActor
    func quitFromMenu() {
        quitApp()
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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
    func runGeneratedCode(
        language: String,
        code: String,
        workingDirectory: String? = nil,
        displayTitle: String? = nil,
        detachSession: Bool = false
    ) {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return }

        guard let launch = buildRunCommandForGeneratedCode(
            language: language,
            code: trimmedCode,
            workspaceDirectory: workingDirectory
        ) else {
            resultText = "Unsupported code language. Use python/bash/sh/zsh."
            resetStreamingMarkdownState()
            isLoading = false
            return
        }

        let normalizedLanguage = launch.language
        let historyInput = displayTitle ?? (normalizedLanguage.isEmpty ? "run code" : "run \(normalizedLanguage) code")
        let pausedCommand = wrapCommandWithPause(launch.command)

        startProgressSession(
            command: pausedCommand,
            displayTitle: historyInput,
            presentation: .terminal,
            runInBackground: false,
            historyType: "run",
            historyInput: historyInput,
            currentDirectory: launch.workingDirectory.path,
            detached: detachSession
        )
    }

    private struct GeneratedCodeLaunch {
        let language: String
        let command: String
        let workingDirectory: URL
    }

    private func buildRunCommandForGeneratedCode(
        language: String,
        code: String,
        workspaceDirectory: String?
    ) -> GeneratedCodeLaunch? {
        guard let resolvedLanguage = normalizeGeneratedCodeLanguage(language: language, code: code) else {
            return nil
        }

        let workspaceURL: URL
        if let workspaceDirectory, !workspaceDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            workspaceURL = URL(fileURLWithPath: workspaceDirectory, isDirectory: true)
        } else if let created = makeGeneratedWorkspace() {
            workspaceURL = created
        } else {
            return nil
        }

        switch resolvedLanguage {
        case "python", "py":
            guard let fileURL = writeGeneratedScript(
                code: code,
                fileExtension: "py",
                workspaceDirectory: workspaceURL
            ) else {
                return nil
            }
            let interpreter = UserDefaults.standard.string(forKey: AppStorageKey.pythonPath) ?? "/usr/bin/python3"
            return GeneratedCodeLaunch(
                language: "python",
                command: "\(shellQuote(interpreter)) \(shellQuote(fileURL.lastPathComponent))",
                workingDirectory: workspaceURL
            )

        case "bash", "sh", "shell":
            guard let fileURL = writeGeneratedScript(
                code: code,
                fileExtension: "sh",
                workspaceDirectory: workspaceURL
            ) else {
                return nil
            }
            return GeneratedCodeLaunch(
                language: "bash",
                command: "/bin/bash \(shellQuote(fileURL.lastPathComponent))",
                workingDirectory: workspaceURL
            )

        case "zsh":
            guard let fileURL = writeGeneratedScript(
                code: code,
                fileExtension: "sh",
                workspaceDirectory: workspaceURL
            ) else {
                return nil
            }
            return GeneratedCodeLaunch(
                language: "zsh",
                command: "/bin/zsh \(shellQuote(fileURL.lastPathComponent))",
                workingDirectory: workspaceURL
            )

        default:
            return nil
        }
    }

    private func normalizeGeneratedCodeLanguage(language: String, code: String) -> String? {
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !normalizedLanguage.isEmpty {
            return normalizedLanguage
        }

        if code.hasPrefix("#!/bin/bash") || code.hasPrefix("#!/usr/bin/env bash") {
            return "bash"
        }
        if code.hasPrefix("#!/bin/zsh") || code.hasPrefix("#!/usr/bin/env zsh") {
            return "zsh"
        }
        if code.hasPrefix("#!/usr/bin/python") || code.hasPrefix("#!/usr/bin/env python") {
            return "python"
        }
        return nil
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

    private func makeGeneratedWorkspace() -> URL? {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("CommanderGenerated", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let workspaceURL = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
            let workspacePath = workspaceURL.path

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3600) {
                try? FileManager.default.removeItem(atPath: workspacePath)
            }

            return workspaceURL
        } catch {
            return nil
        }
    }

    private func writeGeneratedScript(
        code: String,
        fileExtension: String,
        workspaceDirectory: URL
    ) -> URL? {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
            let fileURL = workspaceDirectory.appendingPathComponent("main").appendingPathExtension(fileExtension)
            try code.write(to: fileURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: fileURL.path)

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

    @MainActor
    func deleteHistoryItem(id: UUID) {
        history.removeAll { $0.id == id }
        if let cursor = commandHistoryCursor {
            commandHistoryCursor = cursor < history.count ? cursor : nil
        }
        persistHistory()
    }

    @MainActor
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

    @MainActor
    private func applyHistorySnapshot(_ item: HistoryItem) {
        query = item.query
        resultText = item.result
        resetStreamingMarkdownState()
        isAIResponse = ["ai", "def", "loc"].contains(item.type.lowercased())
        showHistoryView = false
        isLoading = false
    }
}
