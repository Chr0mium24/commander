import Foundation

struct CommandEngineSettings: Encodable {
    let aliasPy: String
    let aliasDef: String
    let aliasAsk: String
    let aliasSer: String

    let pythonPath: String
    let scriptDirectory: String
    let pluginDirectory: String

    let geminiApiKey: String
    let geminiModel: String
    let geminiProxy: String
    let aiProvider: String
    let aiBaseURL: String
    let aiApiKey: String
    let aiModel: String

    let historyLimit: Int
    let autoCopy: Bool
    let streamingMarkdownCommitInterval: Int

    static func current() -> CommandEngineSettings {
        CommandEngineSettings(
            aliasPy: UserDefaults.standard.string(forKey: AppStorageKey.aliasPy) ?? "py",
            aliasDef: UserDefaults.standard.string(forKey: AppStorageKey.aliasDef) ?? "def",
            aliasAsk: UserDefaults.standard.string(forKey: AppStorageKey.aliasAsk) ?? "ask",
            aliasSer: UserDefaults.standard.string(forKey: AppStorageKey.aliasSer) ?? "ser",
            pythonPath: UserDefaults.standard.string(forKey: AppStorageKey.pythonPath) ?? "/usr/bin/python3",
            scriptDirectory: UserDefaults.standard.string(forKey: AppStorageKey.scriptDirectory) ?? "",
            pluginDirectory: UserDefaults.standard.string(forKey: AppStorageKey.pluginDirectory) ?? "",
            geminiApiKey: UserDefaults.standard.string(forKey: AppStorageKey.geminiKey) ?? "",
            geminiModel: UserDefaults.standard.string(forKey: AppStorageKey.geminiModel) ?? "gemini-1.5-flash",
            geminiProxy: UserDefaults.standard.string(forKey: AppStorageKey.geminiProxy) ?? "",
            aiProvider: UserDefaults.standard.string(forKey: AppStorageKey.aiProvider) ?? "",
            aiBaseURL: UserDefaults.standard.string(forKey: AppStorageKey.aiBaseURL) ?? "",
            aiApiKey: UserDefaults.standard.string(forKey: AppStorageKey.aiApiKey) ?? "",
            aiModel: UserDefaults.standard.string(forKey: AppStorageKey.aiModel) ?? "",
            historyLimit: UserDefaults.standard.integer(forKey: AppStorageKey.historyLimit),
            autoCopy: UserDefaults.standard.bool(forKey: AppStorageKey.autoCopy),
            streamingMarkdownCommitInterval: UserDefaults.standard.integer(forKey: AppStorageKey.streamingMarkdownCommitInterval)
        )
    }
}

private struct CommandEngineRequest: Encodable {
    let query: String
    let settings: CommandEngineSettings
}

struct CommandEngineSettingUpdate: Decodable {
    let key: String
    let value: String
    let valueType: String
    
    private enum CodingKeys: String, CodingKey {
        case key
        case value
        case valueType = "value_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        valueType = try container.decodeIfPresent(String.self, forKey: .valueType) ?? "string"
    }
}

struct CommandEngineSettingSchemaItem: Decodable, Identifiable, Hashable {
    let key: String
    let commandKey: String
    let type: String
    let label: String
    let group: String
    let value: String

    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key
        case commandKey = "command_key"
        case type
        case label
        case group
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        commandKey = try container.decodeIfPresent(String.self, forKey: .commandKey) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "string"
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? key
        group = try container.decodeIfPresent(String.self, forKey: .group) ?? "general"
        value = CommandEngineSettingSchemaItem.decodeValueString(from: container)
    }

    private static func decodeValueString(from container: KeyedDecodingContainer<CodingKeys>) -> String {
        if let text = try? container.decode(String.self, forKey: .value) {
            return text
        }
        if let intValue = try? container.decode(Int.self, forKey: .value) {
            return String(intValue)
        }
        if let boolValue = try? container.decode(Bool.self, forKey: .value) {
            return boolValue ? "true" : "false"
        }
        if let doubleValue = try? container.decode(Double.self, forKey: .value) {
            return String(doubleValue)
        }
        return ""
    }
}

struct CommandEngineAIRequest {
    let kind: String
    let provider: String
    let baseURL: String
    let apiKey: String
    let model: String
    let proxyURL: String
}

struct CommandEngineResponse: Decodable {
    let output: String
    let isAIResponse: Bool
    let deferAI: Bool
    let aiPrompt: String
    let aiRequestKind: String
    let aiRequestProvider: String
    let aiRequestBaseURL: String
    let aiRequestAPIKey: String
    let aiRequestModel: String
    let aiRequestProxyURL: String
    let openPanel: Bool
    let panelPresentation: String
    let panelTitle: String
    let panelText: String
    let panelPath: String
    let deferShell: Bool
    let shellCommand: String
    let shellRunInBackground: Bool
    let progressPresentation: String
    let progressTitle: String
    let showHistory: Bool
    let openSettings: Bool
    let shouldQuit: Bool
    let shouldSaveHistory: Bool
    let historyType: String
    let historyInput: String
    let openURL: String?
    let settingUpdates: [CommandEngineSettingUpdate]
    let settingSchema: [CommandEngineSettingSchemaItem]
    let configPaths: [String: String]
    
    private enum CodingKeys: String, CodingKey {
        case output
        case isAIResponse = "is_ai_response"
        case deferAI = "defer_ai"
        case aiPrompt = "ai_prompt"
        case aiRequestKind = "ai_request_kind"
        case aiRequestProvider = "ai_request_provider"
        case aiRequestBaseURL = "ai_request_base_url"
        case aiRequestAPIKey = "ai_request_api_key"
        case aiRequestModel = "ai_request_model"
        case aiRequestProxyURL = "ai_request_proxy_url"
        case openPanel = "open_panel"
        case panelPresentation = "panel_presentation"
        case panelTitle = "panel_title"
        case panelText = "panel_text"
        case panelPath = "panel_path"
        case deferShell = "defer_shell"
        case shellCommand = "shell_command"
        case shellRunInBackground = "shell_run_in_background"
        case progressPresentation = "progress_presentation"
        case progressTitle = "progress_title"
        case showHistory = "show_history"
        case openSettings = "open_settings"
        case shouldQuit = "should_quit"
        case shouldSaveHistory = "should_save_history"
        case historyType = "history_type"
        case historyInput = "history_input"
        case openURL = "open_url"
        case settingUpdates = "setting_updates"
        case settingSchema = "setting_schema"
        case configPaths = "config_paths"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        output = try container.decodeIfPresent(String.self, forKey: .output) ?? ""
        isAIResponse = try container.decodeIfPresent(Bool.self, forKey: .isAIResponse) ?? false
        deferAI = try container.decodeIfPresent(Bool.self, forKey: .deferAI) ?? false
        aiPrompt = try container.decodeIfPresent(String.self, forKey: .aiPrompt) ?? ""
        aiRequestKind = try container.decodeIfPresent(String.self, forKey: .aiRequestKind) ?? ""
        aiRequestProvider = try container.decodeIfPresent(String.self, forKey: .aiRequestProvider) ?? ""
        aiRequestBaseURL = try container.decodeIfPresent(String.self, forKey: .aiRequestBaseURL) ?? ""
        aiRequestAPIKey = try container.decodeIfPresent(String.self, forKey: .aiRequestAPIKey) ?? ""
        aiRequestModel = try container.decodeIfPresent(String.self, forKey: .aiRequestModel) ?? ""
        aiRequestProxyURL = try container.decodeIfPresent(String.self, forKey: .aiRequestProxyURL) ?? ""
        openPanel = try container.decodeIfPresent(Bool.self, forKey: .openPanel) ?? false
        panelPresentation = try container.decodeIfPresent(String.self, forKey: .panelPresentation) ?? ""
        panelTitle = try container.decodeIfPresent(String.self, forKey: .panelTitle) ?? ""
        panelText = try container.decodeIfPresent(String.self, forKey: .panelText) ?? ""
        panelPath = try container.decodeIfPresent(String.self, forKey: .panelPath) ?? ""
        deferShell = try container.decodeIfPresent(Bool.self, forKey: .deferShell) ?? false
        shellCommand = try container.decodeIfPresent(String.self, forKey: .shellCommand) ?? ""
        shellRunInBackground = try container.decodeIfPresent(Bool.self, forKey: .shellRunInBackground) ?? false
        progressPresentation = try container.decodeIfPresent(String.self, forKey: .progressPresentation) ?? "terminal"
        progressTitle = try container.decodeIfPresent(String.self, forKey: .progressTitle) ?? ""
        showHistory = try container.decodeIfPresent(Bool.self, forKey: .showHistory) ?? false
        openSettings = try container.decodeIfPresent(Bool.self, forKey: .openSettings) ?? false
        shouldQuit = try container.decodeIfPresent(Bool.self, forKey: .shouldQuit) ?? false
        shouldSaveHistory = try container.decodeIfPresent(Bool.self, forKey: .shouldSaveHistory) ?? false
        historyType = try container.decodeIfPresent(String.self, forKey: .historyType) ?? ""
        historyInput = try container.decodeIfPresent(String.self, forKey: .historyInput) ?? ""
        openURL = try container.decodeIfPresent(String.self, forKey: .openURL)
        settingUpdates = try container.decodeIfPresent([CommandEngineSettingUpdate].self, forKey: .settingUpdates) ?? []
        settingSchema = try container.decodeIfPresent([CommandEngineSettingSchemaItem].self, forKey: .settingSchema) ?? []
        configPaths = try container.decodeIfPresent([String: String].self, forKey: .configPaths) ?? [:]
    }

    static func failure(_ message: String) -> CommandEngineResponse {
        CommandEngineResponse(
            output: message,
            isAIResponse: false,
            deferAI: false,
            aiPrompt: "",
            aiRequestKind: "",
            aiRequestProvider: "",
            aiRequestBaseURL: "",
            aiRequestAPIKey: "",
            aiRequestModel: "",
            aiRequestProxyURL: "",
            openPanel: false,
            panelPresentation: "",
            panelTitle: "",
            panelText: "",
            panelPath: "",
            deferShell: false,
            shellCommand: "",
            shellRunInBackground: false,
            progressPresentation: "terminal",
            progressTitle: "",
            showHistory: false,
            openSettings: false,
            shouldQuit: false,
            shouldSaveHistory: false,
            historyType: "",
            historyInput: "",
            openURL: nil,
            settingUpdates: [],
            settingSchema: [],
            configPaths: [:]
        )
    }

    init(
        output: String,
        isAIResponse: Bool,
        deferAI: Bool,
        aiPrompt: String,
        aiRequestKind: String,
        aiRequestProvider: String,
        aiRequestBaseURL: String,
        aiRequestAPIKey: String,
        aiRequestModel: String,
        aiRequestProxyURL: String,
        openPanel: Bool,
        panelPresentation: String,
        panelTitle: String,
        panelText: String,
        panelPath: String,
        deferShell: Bool,
        shellCommand: String,
        shellRunInBackground: Bool,
        progressPresentation: String,
        progressTitle: String,
        showHistory: Bool,
        openSettings: Bool,
        shouldQuit: Bool,
        shouldSaveHistory: Bool,
        historyType: String,
        historyInput: String,
        openURL: String?,
        settingUpdates: [CommandEngineSettingUpdate],
        settingSchema: [CommandEngineSettingSchemaItem],
        configPaths: [String: String]
    ) {
        self.output = output
        self.isAIResponse = isAIResponse
        self.deferAI = deferAI
        self.aiPrompt = aiPrompt
        self.aiRequestKind = aiRequestKind
        self.aiRequestProvider = aiRequestProvider
        self.aiRequestBaseURL = aiRequestBaseURL
        self.aiRequestAPIKey = aiRequestAPIKey
        self.aiRequestModel = aiRequestModel
        self.aiRequestProxyURL = aiRequestProxyURL
        self.openPanel = openPanel
        self.panelPresentation = panelPresentation
        self.panelTitle = panelTitle
        self.panelText = panelText
        self.panelPath = panelPath
        self.deferShell = deferShell
        self.shellCommand = shellCommand
        self.shellRunInBackground = shellRunInBackground
        self.progressPresentation = progressPresentation
        self.progressTitle = progressTitle
        self.showHistory = showHistory
        self.openSettings = openSettings
        self.shouldQuit = shouldQuit
        self.shouldSaveHistory = shouldSaveHistory
        self.historyType = historyType
        self.historyInput = historyInput
        self.openURL = openURL
        self.settingUpdates = settingUpdates
        self.settingSchema = settingSchema
        self.configPaths = configPaths
    }

    var aiRequest: CommandEngineAIRequest {
        CommandEngineAIRequest(
            kind: aiRequestKind,
            provider: aiRequestProvider,
            baseURL: aiRequestBaseURL,
            apiKey: aiRequestAPIKey,
            model: aiRequestModel,
            proxyURL: aiRequestProxyURL
        )
    }
}

struct PythonCommandService {
    fileprivate nonisolated static let defaultInterpreter = "/usr/bin/python3"

    static func execute(query: String, settings: CommandEngineSettings) async -> CommandEngineResponse {
        guard let scriptPath = resolveEngineScriptPath() else {
            return .failure("Command engine script not found: python/commander_engine.py")
        }

        let request = CommandEngineRequest(query: query, settings: settings)
        guard
            let requestData = try? JSONEncoder().encode(request),
            let payload = String(data: requestData, encoding: .utf8)
        else {
            return .failure("Failed to encode command request")
        }

        let fallbackInterpreter = settings.pythonPath
        let runResult = await PythonEngineRunner.run(
            scriptPath: scriptPath,
            payload: payload,
            fallbackInterpreter: fallbackInterpreter
        )

        switch runResult {
        case .failure(let message):
            return .failure(message)
        case .success(let raw):
            return decodeCommandEngineResponse(from: raw)
        }
    }

    private static func decodeCommandEngineResponse(from raw: String) -> CommandEngineResponse {
        guard let rawData = raw.data(using: .utf8) else {
            return .failure("Command engine returned non-UTF8 output")
        }

        if let decoded = try? JSONDecoder().decode(CommandEngineResponse.self, from: rawData) {
            return decoded
        }

        if let recovered = recoverJSONObject(from: raw),
           let recoveredData = recovered.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(CommandEngineResponse.self, from: recoveredData) {
            return decoded
        }

        return .failure("Failed to decode command engine response:\n\(raw)")
    }

    private static func recoverJSONObject(from raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}") else {
            return nil
        }
        guard start < end else { return nil }
        return String(raw[start...end])
    }

    private static func resolveEngineScriptPath() -> String? {
        let envPath = ProcessInfo.processInfo.environment["COMMANDER_ENGINE_PATH"]
        let fileManager = FileManager.default

        var candidates: [String] = []
        if let envPath, !envPath.isEmpty {
            candidates.append(envPath)
        }

        candidates.append(
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("python/commander_engine.py")
                .path
        )

        candidates.append(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("python/commander_engine.py")
                .path
        )

        if let bundled = Bundle.main.path(forResource: "commander_engine", ofType: "py") {
            candidates.append(bundled)
        }

        return candidates.first(where: { fileManager.fileExists(atPath: $0) })
    }
}

private enum EngineRunResult: Sendable {
    case success(String)
    case failure(String)
}

private actor PersistentPythonEngine {
    static let shared = PersistentPythonEngine()

    private static let responsePrefix = "__COMMANDER_JSON__:"

    private enum LaunchMode: Equatable {
        case uv(projectDir: String?)
        case interpreter(path: String)
    }

    private struct LaunchConfiguration: Equatable {
        let scriptPath: String
        let mode: LaunchMode
    }

    private var configuration: LaunchConfiguration?
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputIterator: AsyncThrowingStream<String, Error>.Iterator?

    func run(
        scriptPath: String,
        payload: String,
        fallbackInterpreter: String
    ) async -> EngineRunResult {
        let projectDir = PythonEngineRunner.resolveUVProjectDir(scriptPath: scriptPath)
        let interpreter = PythonEngineRunner.resolvedInterpreter(from: fallbackInterpreter)

        let launchConfigurations: [LaunchConfiguration] = [
            LaunchConfiguration(scriptPath: scriptPath, mode: .uv(projectDir: projectDir)),
            LaunchConfiguration(scriptPath: scriptPath, mode: .interpreter(path: interpreter)),
        ]

        var lastError = "Failed to communicate with the command engine."
        for launchConfiguration in launchConfigurations {
            let result = await performRequest(payload: payload, configuration: launchConfiguration)
            switch result {
            case .success:
                return result
            case .failure(let message):
                lastError = message
            }
        }

        return .failure(lastError)
    }

    private func performRequest(
        payload: String,
        configuration: LaunchConfiguration
    ) async -> EngineRunResult {
        do {
            try ensureProcess(for: configuration)
            guard let inputHandle else {
                invalidateProcess()
                return .failure("Command engine input pipe is unavailable.")
            }

            if let data = "\(payload)\n".data(using: .utf8) {
                try inputHandle.write(contentsOf: data)
            } else {
                return .failure("Failed to encode command engine payload.")
            }

            guard let rawResponse = await nextResponseLine() else {
                invalidateProcess()
                return .failure("Persistent command engine exited before returning a response.")
            }

            return .success(rawResponse)
        } catch {
            invalidateProcess()
            return .failure("Failed to communicate with the command engine: \(error.localizedDescription)")
        }
    }

    private func ensureProcess(for newConfiguration: LaunchConfiguration) throws {
        if configuration == newConfiguration,
           let process,
           process.isRunning,
           inputHandle != nil,
           outputIterator != nil {
            return
        }

        invalidateProcess()

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let process = Process()

        switch newConfiguration.mode {
        case .uv(let projectDir):
            process.executableURL = URL(fileURLWithPath: PythonEngineRunner.envExecutable)
            var arguments = ["uv", "run"]
            if let projectDir, !projectDir.isEmpty {
                arguments += ["--project", projectDir]
            }
            arguments += ["python", "-u", newConfiguration.scriptPath, "--stdio"]
            process.arguments = arguments
            process.environment = PythonEngineRunner.uvEnvironment(projectDir: projectDir)

        case .interpreter(let path):
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["-u", newConfiguration.scriptPath, "--stdio"]
        }

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        configuration = newConfiguration
        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        outputIterator = makeOutputIterator(handle: outputPipe.fileHandleForReading)
    }

    private func makeOutputIterator(
        handle: FileHandle
    ) -> AsyncThrowingStream<String, Error>.Iterator {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task.detached {
                do {
                    for try await line in handle.bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return stream.makeAsyncIterator()
    }

    private func nextResponseLine() async -> String? {
        while true {
            guard var iterator = outputIterator else { return nil }

            do {
                guard let line = try await iterator.next() else {
                    outputIterator = nil
                    return nil
                }
                outputIterator = iterator

                guard let prefixRange = line.range(of: Self.responsePrefix) else {
                    continue
                }

                return String(line[prefixRange.upperBound...])
            } catch {
                outputIterator = nil
                return nil
            }
        }
    }

    private func invalidateProcess() {
        inputHandle?.closeFile()
        inputHandle = nil
        outputIterator = nil

        if let process {
            if process.isRunning {
                process.terminate()
            }
            self.process = nil
        }

        configuration = nil
    }
}

private enum PythonEngineRunner {
    nonisolated fileprivate static let envExecutable = "/usr/bin/env"

    static func run(
        scriptPath: String,
        payload: String,
        fallbackInterpreter: String
    ) async -> EngineRunResult {
        let persistentResult = await PersistentPythonEngine.shared.run(
            scriptPath: scriptPath,
            payload: payload,
            fallbackInterpreter: fallbackInterpreter
        )

        switch persistentResult {
        case .success:
            return persistentResult
        case .failure:
            break
        }

        return runOneShot(
            scriptPath: scriptPath,
            payload: payload,
            fallbackInterpreter: fallbackInterpreter
        )
    }

    nonisolated private static func runOneShot(
        scriptPath: String,
        payload: String,
        fallbackInterpreter: String
    ) -> EngineRunResult {
        switch runWithUV(scriptPath: scriptPath, payload: payload) {
        case .success(let raw):
            return .success(raw)
        case .missingTool:
            break
        case .failure(let message):
            return .failure(message)
        }

        let interpreter = resolvedInterpreter(from: fallbackInterpreter)
        return runWithInterpreter(interpreter: interpreter, scriptPath: scriptPath, payload: payload)
    }

    nonisolated private static func runWithUV(scriptPath: String, payload: String) -> UVRunResult {
        var arguments = ["uv", "run"]
        let projectDir = resolveUVProjectDir(scriptPath: scriptPath)
        if let projectDir {
            arguments += ["--project", projectDir]
        }
        arguments += ["python", scriptPath, payload]

        let outcome = runProcess(
            executable: envExecutable,
            arguments: arguments,
            environment: uvEnvironment(projectDir: projectDir)
        )
        switch outcome {
        case .launchFailed(let errorMessage):
            return .failure("Failed to run command engine via uv: \(errorMessage)")
        case .completed(let status, let output):
            if status == 0 {
                let raw = output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else {
                    return .failure("Command engine returned empty output")
                }
                return .success(raw)
            }

            if looksLikeMissingUV(status: status, output: output) {
                return .missingTool
            }

            let message = output.isEmpty
                ? "uv run failed with exit code \(status)."
                : output
            return .failure("Failed to run command engine via uv:\n\(message)")
        }
    }

    nonisolated private static func runWithInterpreter(
        interpreter: String,
        scriptPath: String,
        payload: String
    ) -> EngineRunResult {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: interpreter)
        process.arguments = [scriptPath, payload]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else {
                return .failure("Command engine returned empty output")
            }

            return .success(raw)
        } catch {
            return .failure("Failed to run command engine: \(error.localizedDescription)")
        }
    }

    nonisolated fileprivate static func resolvedInterpreter(from configured: String) -> String {
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PythonCommandService.defaultInterpreter
        }
        guard trimmed.hasPrefix("/") else {
            return PythonCommandService.defaultInterpreter
        }
        guard FileManager.default.fileExists(atPath: trimmed) else {
            return PythonCommandService.defaultInterpreter
        }
        return trimmed
    }

    nonisolated fileprivate static func resolveUVProjectDir(scriptPath: String) -> String? {
        let fileManager = FileManager.default

        var candidates: [String] = []
        if let envPath = ProcessInfo.processInfo.environment["COMMANDER_UV_PROJECT"],
           !envPath.isEmpty {
            candidates.append(envPath)
        }

        candidates.append(fileManager.currentDirectoryPath)
        candidates.append(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .path
        )

        var currentURL = URL(fileURLWithPath: scriptPath).deletingLastPathComponent()
        for _ in 0..<8 {
            candidates.append(currentURL.path)
            let parent = currentURL.deletingLastPathComponent()
            if parent.path == currentURL.path {
                break
            }
            currentURL = parent
        }

        var seen = Set<String>()
        for path in candidates {
            let normalized = URL(fileURLWithPath: path).standardized.path
            guard seen.insert(normalized).inserted else { continue }
            let pyprojectPath = URL(fileURLWithPath: normalized)
                .appendingPathComponent("pyproject.toml")
                .path
            if fileManager.fileExists(atPath: pyprojectPath) {
                return normalized
            }
        }

        return nil
    }

    nonisolated private static func looksLikeMissingUV(status: Int32, output: String) -> Bool {
        guard status == 127 || status == 126 else { return false }
        let lowered = output.lowercased()
        return lowered.contains("uv: no such file")
            || lowered.contains("command not found")
            || lowered.contains("can't find")
    }

    nonisolated fileprivate static func uvEnvironment(projectDir: String?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "VIRTUAL_ENV")

        let fileManager = FileManager.default
        let envOverride = environment["COMMANDER_UV_ENV_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let envOverride, !envOverride.isEmpty {
            environment["UV_PROJECT_ENVIRONMENT"] = envOverride
        } else if let projectDir, !projectDir.isEmpty {
            let folderName = URL(fileURLWithPath: projectDir).lastPathComponent
            let cacheRoot = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Caches/Commander", isDirectory: true)
            let envPath = cacheRoot
                .appendingPathComponent("uv-env-\(folderName)", isDirectory: true)
                .path
            if !fileManager.fileExists(atPath: cacheRoot.path) {
                try? fileManager.createDirectory(atPath: cacheRoot.path, withIntermediateDirectories: true)
            }
            environment["UV_PROJECT_ENVIRONMENT"] = envPath
        }

        if environment["UV_CACHE_DIR"]?.isEmpty != false {
            let cachePath = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Caches/Commander/uv-cache", isDirectory: true)
                .path
            environment["UV_CACHE_DIR"] = cachePath
        }

        return environment
    }

    nonisolated private static func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> ProcessRunOutcome {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .completed(status: process.terminationStatus, output: output)
        } catch {
            return .launchFailed("Process launch failed: \(error.localizedDescription)")
        }
    }
}

private enum UVRunResult {
    case success(String)
    case missingTool
    case failure(String)
}

private enum ProcessRunOutcome {
    case completed(status: Int32, output: String)
    case launchFailed(String)
}
