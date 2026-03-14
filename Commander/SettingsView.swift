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
}
