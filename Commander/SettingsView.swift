import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import AppKit
internal import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(AppStorageKey.launchAtLogin) private var launchAtLogin = false
    @AppStorage(AppStorageKey.historyLimit) private var historyLimit = 50
    @AppStorage(AppStorageKey.autoCopy) private var autoCopy = false
    @AppStorage(AppStorageKey.multilineInput) private var multilineInput = false

    @AppStorage(AppStorageKey.geminiKey) private var geminiKey = ""
    @AppStorage(AppStorageKey.geminiModel) private var geminiModel = "gemini-1.5-flash"
    @AppStorage(AppStorageKey.geminiProxy) private var geminiProxy = ""
    @AppStorage(AppStorageKey.aiProvider) private var aiProvider = ""
    @AppStorage(AppStorageKey.aiBaseURL) private var aiBaseURL = ""
    @AppStorage(AppStorageKey.aiApiKey) private var aiApiKey = ""
    @AppStorage(AppStorageKey.aiModel) private var aiModel = ""

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
                commandExample("set script_dir /Users/you/scripts")
                commandExample("set plugin_dir ~/Library/Application\\ Support/Commander/plugins")
                commandExample("set ai_base_url https://api.edgefn.net/v1/chat/completions")
                commandExample("set ai_api_key sk-...")
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

                    Button("Reload Schema") {
                        Task {
                            await loadDynamicSchema(force: true)
                        }
                    }
                    .buttonStyle(.bordered)
                }

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

                if let configPath = dynamicConfigPaths["user_config"], !configPath.isEmpty {
                    Text("Config: \(configPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if dynamicSchema.isEmpty && !isDynamicLoading {
                    Text("No dynamic schema returned by command engine.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(groupedDynamicSchema, id: \.group) { groupBlock in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(groupBlock.group.capitalized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        ForEach(groupBlock.items) { item in
                            dynamicSettingRow(item)
                                .padding(10)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
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
        let grouped = Dictionary(grouping: dynamicSchema) { item in
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
        let query = "set \(commandKey) \(quoteSetValue(setValue))"

        Task {
            let response = await PythonCommandService.execute(
                query: query,
                settings: CommandEngineSettings.current()
            )
            await MainActor.run {
                dynamicStatusMessage = response.output
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
        if force || dynamicValues.isEmpty {
            var initial: [String: String] = [:]
            for item in dynamicSchema {
                initial[item.key] = initialValue(for: item)
            }
            dynamicValues = initial
        }
        dynamicStatusMessage = response.output
        didLoadDynamicSchema = true
    }
}
