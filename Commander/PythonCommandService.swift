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
            autoCopy: UserDefaults.standard.bool(forKey: AppStorageKey.autoCopy)
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

struct CommandEngineResponse: Decodable {
    let output: String
    let isAIResponse: Bool
    let deferAI: Bool
    let aiPrompt: String
    let deferShell: Bool
    let shellCommand: String
    let shellRunInBackground: Bool
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
        case deferShell = "defer_shell"
        case shellCommand = "shell_command"
        case shellRunInBackground = "shell_run_in_background"
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
        deferShell = try container.decodeIfPresent(Bool.self, forKey: .deferShell) ?? false
        shellCommand = try container.decodeIfPresent(String.self, forKey: .shellCommand) ?? ""
        shellRunInBackground = try container.decodeIfPresent(Bool.self, forKey: .shellRunInBackground) ?? false
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
            deferShell: false,
            shellCommand: "",
            shellRunInBackground: false,
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
        deferShell: Bool,
        shellCommand: String,
        shellRunInBackground: Bool,
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
        self.deferShell = deferShell
        self.shellCommand = shellCommand
        self.shellRunInBackground = shellRunInBackground
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
}

struct PythonCommandService {
    fileprivate static let defaultInterpreter = "/usr/bin/python3"

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
        let runResult = await Task.detached {
            PythonEngineRunner.run(
                scriptPath: scriptPath,
                payload: payload,
                fallbackInterpreter: fallbackInterpreter
            )
        }.value

        switch runResult {
        case .failure(let message):
            return .failure(message)
        case .success(let raw):
            guard let rawData = raw.data(using: .utf8) else {
                return .failure("Command engine returned non-UTF8 output")
            }

            do {
                return try JSONDecoder().decode(CommandEngineResponse.self, from: rawData)
            } catch {
                return .failure("Failed to decode command engine response:\n\(raw)")
            }
        }
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

private enum PythonEngineRunner {
    private static let envExecutable = "/usr/bin/env"

    nonisolated static func run(
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
        if let projectDir = resolveUVProjectDir(scriptPath: scriptPath) {
            arguments += ["--project", projectDir]
        }
        arguments += ["python", scriptPath, payload]

        let outcome = runProcess(executable: envExecutable, arguments: arguments)
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

    nonisolated private static func resolvedInterpreter(from configured: String) -> String {
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

    nonisolated private static func resolveUVProjectDir(scriptPath: String) -> String? {
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

    nonisolated private static func runProcess(
        executable: String,
        arguments: [String]
    ) -> ProcessRunOutcome {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
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
