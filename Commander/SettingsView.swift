import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import AppKit
import Foundation
internal import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(AppStorageKey.launchAtLogin) private var launchAtLogin = false
    @AppStorage(AppStorageKey.historyLimit) private var historyLimit = 50
    @AppStorage(AppStorageKey.autoCopy) private var autoCopy = false
    @AppStorage(AppStorageKey.streamingMarkdownCommitInterval) private var streamingMarkdownCommitInterval = 50
    @AppStorage(AppStorageKey.multilineInput) private var multilineInput = false

    @AppStorage(AppStorageKey.geminiKey) private var geminiKey = ""
    @AppStorage(AppStorageKey.geminiModel) private var geminiModel = "gemini-1.5-flash"
    @AppStorage(AppStorageKey.geminiProxy) private var geminiProxy = ""
    @AppStorage(AppStorageKey.aiProvider) private var aiProvider = ""
    @AppStorage(AppStorageKey.aiBaseURL) private var aiBaseURL = ""
    @AppStorage(AppStorageKey.aiApiKey) private var aiApiKey = ""
    @AppStorage(AppStorageKey.aiModel) private var aiModel = ""
    @AppStorage(AppStorageKey.aiSystemPrompt) private var aiSystemPrompt = ""

    @AppStorage(AppStorageKey.aliasDef) private var aliasDef = "def"
    @AppStorage(AppStorageKey.aliasAsk) private var aliasAsk = "ask"
    @AppStorage(AppStorageKey.aliasSer) private var aliasSer = "ser"
    @AppStorage(AppStorageKey.aliasPy) private var aliasPy = "py"

    @AppStorage(AppStorageKey.pythonPath) private var pythonPath = "/usr/bin/python3"
    @AppStorage(AppStorageKey.scriptDirectory) private var scriptDirectory = ""
    @AppStorage(AppStorageKey.pluginDirectory) private var pluginDirectory = ""

    @State private var showFolderImporter = false
    @State private var showPluginFolderImporter = false
    @State private var dynamicSchema: [CommandEngineSettingSchemaItem] = []
    @State private var dynamicValues: [String: String] = [:]
    @State private var dynamicConfigPaths: [String: String] = [:]
    @State private var dynamicStatusMessage = ""
    @State private var isDynamicLoading = false
    @State private var didLoadDynamicSchema = false
    @State private var dynamicSearchText = ""
    @State private var dynamicCollapsedGroups: Set<String> = []
    @State private var dynamicBaseValues: [String: String] = [:]
    @State private var showDynamicJSONImporter = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            aiTab
                .tabItem { Label("AI Service", systemImage: "brain.head.profile") }

            aliasesTab
                .tabItem { Label("Aliases", systemImage: "keyboard") }

            commandTab
                .tabItem { Label("Commands", systemImage: "terminal") }

            dynamicTab
                .tabItem { Label("Dynamic", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 560, height: 460)
        .padding()
    }

    private var generalTab: some View {
        Form {
            Section("System") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(enabled: newValue)
                    }

                HStack {
                    Text("Global Hotkey")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .toggleWindow)
                }
            }

            Section("Behavior") {
                Stepper(value: $historyLimit, in: 0...200) {
                    HStack {
                        Text("History Limit")
                        Spacer()
                        Text("\(historyLimit)")
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Auto-copy Result", isOn: $autoCopy)
                Stepper(value: $streamingMarkdownCommitInterval, in: 10...500, step: 10) {
                    HStack {
                        Text("Streaming Markdown Batch Chars")
                        Spacer()
                        Text("\(streamingMarkdownCommitInterval)")
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Multiline Input", isOn: $multilineInput)
            }

            Section("Environment") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Python Interpreter Path")
                    TextField("/usr/bin/python3", text: $pythonPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Script Directory")
                    HStack {
                        TextField("Path to scripts folder", text: $scriptDirectory)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button("Browse") {
                            showFolderImporter = true
                        }
                    }

                    Text("Use `run <name>` to execute `<name>.sh` / `<name>.py` from this directory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Plugin Directory")
                    HStack {
                        TextField("Path to commander plugins folder", text: $pluginDirectory)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button("Browse") {
                            showPluginFolderImporter = true
                        }
                    }

                    Text("Use `plugins` and `plugins inspect` to check load status.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Advanced Files") {
                HStack(spacing: 10) {
                    Button("Open User Config") {
                        openUserConfigFile()
                    }
                    Button("Open Plugin Directory") {
                        openPluginDirectory()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            let _ = url.startAccessingSecurityScopedResource()
            scriptDirectory = url.path
        }
        .fileImporter(
            isPresented: $showPluginFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            let _ = url.startAccessingSecurityScopedResource()
            pluginDirectory = url.path
        }
    }

    private var aiTab: some View {
        Form {
            Section("Gemini Streaming (Built-in)") {
                SecureField("API Key", text: $geminiKey)
                TextField("Model Name", text: $geminiModel)
                Text("Default: gemini-1.5-flash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Network") {
                TextField("Proxy URL (Optional)", text: $geminiProxy, prompt: Text("https://your-proxy.com"))
                Text("Leave empty to use the default Gemini API endpoint.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("OpenAI-Compatible Plugins") {
                TextField("Provider Name (Optional)", text: $aiProvider, prompt: Text("edgefn / openai_compatible"))
                TextField("Base URL", text: $aiBaseURL, prompt: Text("https://api.edgefn.net/v1/chat/completions"))
                SecureField("API Key", text: $aiApiKey)
                TextField("Model", text: $aiModel, prompt: Text("DeepSeek-V3.2"))
                Text("These fields are consumed by Python plugins (for example `edge` command).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Prompting") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Prompt")
                    TextEditor(text: $aiSystemPrompt)
                        .frame(minHeight: 90)
                        .font(.system(.body, design: .monospaced))
                    Text("Applied to built-in AI chat requests. Example: require inline math to use `$...$`.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aliasesTab: some View {
        Form {
            Section("Custom Triggers") {
                aliasRow(title: "Dictionary", text: $aliasDef, placeholder: "def")
                aliasRow(title: "AI Chat", text: $aliasAsk, placeholder: "ask")
                aliasRow(title: "Web Search", text: $aliasSer, placeholder: "ser")
                aliasRow(title: "Python Code", text: $aliasPy, placeholder: "py")
            }

            Section {
                Text("Aliases only affect command words. Example: if Dictionary alias is `dict`, use `dict apple`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var commandTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Command-based Settings")
                    .font(.headline)

                Text("You can read or update settings directly in Commander.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                commandExample("set get gemini_model")
                commandExample("set gemini_model gemini-1.5-flash")
                commandExample("set auto_copy true")
                commandExample("set history_limit 50")
                commandExample("set streaming_markdown_commit_interval 50")
                commandExample("set script_dir /Users/you/scripts")
                commandExample("set plugin_dir ~/Library/Application\\ Support/Commander/plugins")
                commandExample("set ai_base_url https://api.edgefn.net/v1/chat/completions")
                commandExample("set ai_api_key sk-...")
                commandExample("set ai_system_prompt 回答里的行内公式必须使用$...$包裹")
                commandExample("set")
                commandExample("plugins inspect")

                Text("`set` without arguments opens this settings window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var dynamicTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Dynamic Settings Schema")
                        .font(.headline)

                    Spacer()

                    Button("Copy Visible JSON") {
                        copyVisibleDynamicSettingsJSON()
                    }
                    .buttonStyle(.bordered)
                    .disabled(filteredDynamicSchema.isEmpty)

                    Button("Import JSON") {
                        showDynamicJSONImporter = true
                    }
                    .buttonStyle(.bordered)

                    Button("Apply Changed") {
                        Task {
                            await applyAllChangedDynamicSettings()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(changedDynamicSettingCount == 0 || isDynamicLoading)

                    Button("Reload Schema") {
                        Task {
                            await loadDynamicSchema(force: true)
                        }
                    }
                    .buttonStyle(.bordered)
                }

                TextField("Search label/key/group", text: $dynamicSearchText)
                    .textFieldStyle(.roundedBorder)

                if isDynamicLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading schema...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !dynamicStatusMessage.isEmpty {
                    Text(dynamicStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Changed: \(changedDynamicSettingCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let configPath = dynamicConfigPaths["user_config"], !configPath.isEmpty {
                    HStack(spacing: 8) {
                        Text("Config: \(configPath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open") {
                            openUserConfigFile()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if dynamicSchema.isEmpty && !isDynamicLoading {
                    Text("No dynamic schema returned by command engine.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(groupedDynamicSchema, id: \.group) { groupBlock in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Button(action: {
                                toggleGroupCollapse(group: groupBlock.group)
                            }) {
                                Label(
                                    groupBlock.group.capitalized,
                                    systemImage: isGroupCollapsed(groupBlock.group) ? "chevron.right" : "chevron.down"
                                )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)

                            Spacer()

                            Text("\(groupBlock.items.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if !isGroupCollapsed(groupBlock.group) {
                            ForEach(groupBlock.items) { item in
                                dynamicSettingRow(item)
                                    .padding(10)
                                    .background(Color.primary.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .task {
            await loadDynamicSchema(force: false)
        }
        .fileImporter(
            isPresented: $showDynamicJSONImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleDynamicJSONImport(result)
        }
    }

    @ViewBuilder
    private func aliasRow(title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
        }
    }

    @ViewBuilder
    private func commandExample(_ command: String) -> some View {
        Text(command)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toggleLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }

    private func openUserConfigFile() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Commander", isDirectory: true)
        let configPath = appSupport.appendingPathComponent("config.json")

        if !FileManager.default.fileExists(atPath: configPath.path) {
            let template = """
            {
              "pluginDirectory": "",
              "aiBaseURL": "",
              "aiApiKey": "",
              "aiModel": ""
            }
            """
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            try? template.write(to: configPath, atomically: true, encoding: .utf8)
        }

        NSWorkspace.shared.open(configPath)
    }

    private func openPluginDirectory() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Commander", isDirectory: true)
        let pluginPath = appSupport.appendingPathComponent("plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: pluginPath, withIntermediateDirectories: true)
        NSWorkspace.shared.open(pluginPath)
    }

    private var groupedDynamicSchema: [(group: String, items: [CommandEngineSettingSchemaItem])] {
        let grouped = Dictionary(grouping: filteredDynamicSchema) { item in
            item.group.isEmpty ? "general" : item.group.lowercased()
        }
        return grouped
            .map { key, value in
                (
                    group: key,
                    items: value.sorted {
                        let lhs = $0.label.isEmpty ? $0.commandKey : $0.label
                        let rhs = $1.label.isEmpty ? $1.commandKey : $1.label
                        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                    }
                )
            }
            .sorted { $0.group.localizedCaseInsensitiveCompare($1.group) == .orderedAscending }
    }

    private var filteredDynamicSchema: [CommandEngineSettingSchemaItem] {
        let keyword = dynamicSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return dynamicSchema }

        return dynamicSchema.filter { item in
            item.key.lowercased().contains(keyword)
                || item.commandKey.lowercased().contains(keyword)
                || item.label.lowercased().contains(keyword)
                || item.group.lowercased().contains(keyword)
        }
    }

    @ViewBuilder
    private func dynamicSettingRow(_ item: CommandEngineSettingSchemaItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(item.label.isEmpty ? item.key : item.label)
                Spacer()
                Text(item.commandKey)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(item.type)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if normalizedDynamicType(item.type) == "bool" {
                Toggle("Enabled", isOn: boolBinding(for: item))
                    .toggleStyle(.switch)
            } else {
                HStack(spacing: 8) {
                    if normalizedDynamicType(item.type) == "secret" {
                        SecureField(item.key, text: textBinding(for: item))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        TextField(item.key, text: textBinding(for: item))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    Button("Apply") {
                        applyDynamicSetting(item)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func textBinding(for item: CommandEngineSettingSchemaItem) -> Binding<String> {
        Binding(
            get: {
                dynamicValues[item.key] ?? initialValue(for: item)
            },
            set: { newValue in
                dynamicValues[item.key] = newValue
            }
        )
    }

    private func boolBinding(for item: CommandEngineSettingSchemaItem) -> Binding<Bool> {
        Binding(
            get: {
                boolFromString(dynamicValues[item.key] ?? initialValue(for: item))
            },
            set: { newValue in
                let stringValue = newValue ? "true" : "false"
                dynamicValues[item.key] = stringValue
                applyDynamicSetting(item, explicitValue: stringValue)
            }
        )
    }

    private func initialValue(for item: CommandEngineSettingSchemaItem) -> String {
        if !item.value.isEmpty {
            return item.value
        }

        let defaults = UserDefaults.standard
        let type = normalizedDynamicType(item.type)

        if type == "bool" {
            if let value = defaults.object(forKey: item.key) as? Bool {
                return value ? "true" : "false"
            }
            return "false"
        }

        if type == "int" {
            if let value = defaults.object(forKey: item.key) as? Int {
                return "\(value)"
            }
            if let value = defaults.string(forKey: item.key) {
                return value
            }
            return ""
        }

        return defaults.string(forKey: item.key) ?? ""
    }

    private func normalizedDynamicType(_ type: String) -> String {
        let lowered = type.lowercased()
        if lowered == "boolean" { return "bool" }
        if lowered == "integer" { return "int" }
        return lowered
    }

    private func isGroupCollapsed(_ group: String) -> Bool {
        dynamicCollapsedGroups.contains(group)
    }

    private func toggleGroupCollapse(group: String) {
        if dynamicCollapsedGroups.contains(group) {
            dynamicCollapsedGroups.remove(group)
        } else {
            dynamicCollapsedGroups.insert(group)
        }
    }

    private func boolFromString(_ value: String) -> Bool {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered == "1" || lowered == "true" || lowered == "yes" || lowered == "on"
    }

    private func applyDynamicSetting(_ item: CommandEngineSettingSchemaItem, explicitValue: String? = nil) {
        let rawValue = explicitValue ?? dynamicValues[item.key] ?? initialValue(for: item)
        dynamicValues[item.key] = rawValue
        applyToUserDefaults(item: item, rawValue: rawValue)

        let commandKey = item.commandKey.isEmpty ? item.key : item.commandKey
        let setValue = normalizedDynamicType(item.type) == "bool" ? (boolFromString(rawValue) ? "true" : "false") : rawValue
        Task {
            let response = await applyDynamicSettingValue(commandKey: commandKey, value: setValue)
            await MainActor.run {
                dynamicStatusMessage = response.output
                dynamicBaseValues[item.key] = setValue
            }
        }
    }

    private func applyToUserDefaults(item: CommandEngineSettingSchemaItem, rawValue: String) {
        let defaults = UserDefaults.standard
        let type = normalizedDynamicType(item.type)

        if type == "bool" {
            defaults.set(boolFromString(rawValue), forKey: item.key)
            return
        }

        if type == "int" {
            if let intValue = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                defaults.set(intValue, forKey: item.key)
            } else {
                defaults.set(rawValue, forKey: item.key)
            }
            return
        }

        defaults.set(rawValue, forKey: item.key)
    }

    private func quoteSetValue(_ value: String) -> String {
        if value.isEmpty {
            return "\"\""
        }
        if !needsQuoting(value) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func needsQuoting(_ value: String) -> Bool {
        value.contains(" ")
            || value.contains("\t")
            || value.contains("\n")
            || value.contains("'")
            || value.contains("\"")
    }

    @MainActor
    private func loadDynamicSchema(force: Bool) async {
        if isDynamicLoading {
            return
        }
        if didLoadDynamicSchema && !force {
            return
        }

        isDynamicLoading = true
        defer { isDynamicLoading = false }

        let response = await PythonCommandService.execute(
            query: "set schema_json",
            settings: CommandEngineSettings.current()
        )

        dynamicSchema = response.settingSchema.filter { !$0.key.isEmpty }
        dynamicConfigPaths = response.configPaths
        var mergedValues = dynamicValues
        var newBaseValues: [String: String] = [:]
        for item in dynamicSchema {
            let baseValue = normalizedStoredValue(for: item, value: initialValue(for: item))
            newBaseValues[item.key] = baseValue
            if force || mergedValues[item.key] == nil {
                mergedValues[item.key] = baseValue
            }
        }
        dynamicValues = mergedValues
        dynamicBaseValues = newBaseValues
        dynamicStatusMessage = response.output
        didLoadDynamicSchema = true
    }

    private func copyVisibleDynamicSettingsJSON() {
        var payload: [String: String] = [:]
        for item in filteredDynamicSchema {
            payload[item.key] = dynamicValues[item.key] ?? initialValue(for: item)
        }

        guard
            let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let text = String(data: data, encoding: .utf8)
        else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        dynamicStatusMessage = "Copied visible dynamic settings as JSON."
    }

    private var changedDynamicSettingCount: Int {
        dynamicSchema.reduce(into: 0) { partial, item in
            let current = normalizedStoredValue(for: item, value: dynamicValues[item.key] ?? initialValue(for: item))
            let base = dynamicBaseValues[item.key] ?? normalizedStoredValue(for: item, value: initialValue(for: item))
            if current != base {
                partial += 1
            }
        }
    }

    private func normalizedStoredValue(for item: CommandEngineSettingSchemaItem, value: String) -> String {
        if normalizedDynamicType(item.type) == "bool" {
            return boolFromString(value) ? "true" : "false"
        }
        return value
    }

    @MainActor
    private func applyAllChangedDynamicSettings() async {
        if isDynamicLoading {
            return
        }
        isDynamicLoading = true
        defer { isDynamicLoading = false }

        var changedItems: [(item: CommandEngineSettingSchemaItem, value: String)] = []
        for item in dynamicSchema {
            let current = normalizedStoredValue(for: item, value: dynamicValues[item.key] ?? initialValue(for: item))
            let base = dynamicBaseValues[item.key] ?? normalizedStoredValue(for: item, value: initialValue(for: item))
            if current != base {
                changedItems.append((item: item, value: current))
            }
        }

        guard !changedItems.isEmpty else {
            dynamicStatusMessage = "No changed settings to apply."
            return
        }

        var appliedCount = 0
        var lastMessage = ""
        for pair in changedItems {
            let commandKey = pair.item.commandKey.isEmpty ? pair.item.key : pair.item.commandKey
            let response = await applyDynamicSettingValue(commandKey: commandKey, value: pair.value)
            lastMessage = response.output
            if !response.output.lowercased().contains("unknown key")
                && !response.output.lowercased().contains("expects")
            {
                appliedCount += 1
                dynamicBaseValues[pair.item.key] = pair.value
            } else {
                break
            }
        }

        dynamicStatusMessage = "Applied \(appliedCount)/\(changedItems.count). \(lastMessage)"
    }

    private func applyDynamicSettingValue(commandKey: String, value: String) async -> CommandEngineResponse {
        let query = "set \(commandKey) \(quoteSetValue(value))"
        return await PythonCommandService.execute(
            query: query,
            settings: CommandEngineSettings.current()
        )
    }

    private func handleDynamicJSONImport(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }
        let _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else {
            dynamicStatusMessage = "Failed to read JSON file."
            return
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any]
        else {
            dynamicStatusMessage = "Invalid JSON format. Expect object: {\"key\": value}"
            return
        }

        let schemaByStorageKey = Dictionary(uniqueKeysWithValues: dynamicSchema.map { ($0.key, $0) })
        let schemaByCommandKey = Dictionary(uniqueKeysWithValues: dynamicSchema.map { ($0.commandKey, $0) })

        var imported = 0
        var skipped = 0
        for (rawKey, rawValue) in dict {
            let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else { continue }
            let matched = schemaByStorageKey[trimmedKey] ?? schemaByCommandKey[trimmedKey]
            guard let item = matched else {
                skipped += 1
                continue
            }

            let stringValue = stringifyImportedJSONValue(rawValue)
            dynamicValues[item.key] = normalizedStoredValue(for: item, value: stringValue)
            applyToUserDefaults(item: item, rawValue: stringValue)
            imported += 1
        }

        dynamicStatusMessage = "Imported \(imported) settings from JSON, skipped \(skipped). Click 'Apply Changed' to persist via Python config."
    }

    private func stringifyImportedJSONValue(_ value: Any) -> String {
        if let stringValue = value as? String {
            return stringValue
        }
        if let boolValue = value as? Bool {
            return boolValue ? "true" : "false"
        }
        if let intValue = value as? Int {
            return String(intValue)
        }
        if let doubleValue = value as? Double {
            if doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                return String(Int(doubleValue))
            }
            return String(doubleValue)
        }
        return String(describing: value)
    }
}
