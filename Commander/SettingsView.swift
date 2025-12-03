import SwiftUI
import KeyboardShortcuts
import ServiceManagement
internal import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(AppStorageKey.launchAtLogin) var launchAtLogin = false
    @AppStorage(AppStorageKey.historyLimit) var historyLimit = 50
    @AppStorage(AppStorageKey.autoCopy) var autoCopy = false
    
    @AppStorage(AppStorageKey.geminiKey) var geminiKey = ""
    @AppStorage(AppStorageKey.geminiModel) var geminiModel = "gemini-1.5-flash"
    @AppStorage(AppStorageKey.geminiProxy) var geminiProxy = "" // [新增]
    
    @AppStorage(AppStorageKey.aliasDef) var aliasDef = "def"
    @AppStorage(AppStorageKey.aliasAsk) var aliasAsk = "ask"
    @AppStorage(AppStorageKey.aliasSer) var aliasSer = "ser"
    @AppStorage(AppStorageKey.pythonPath) var pythonPath = "/usr/bin/python3"
    @AppStorage(AppStorageKey.aliasPy) var aliasPy = "py"
    
    // [新增] 脚本目录路径
        @AppStorage(AppStorageKey.scriptDirectory) var scriptDirectory = ""
        
        // [新增] 用于控制文件夹选择器显示
        @State private var showFolderImporter = false
    
    var body: some View {
        TabView {
            // --- Tab 1: General ---
            Form {
                // 使用 Section 让布局在 macOS 设置窗口中更规范
                Section {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            toggleLaunchAtLogin(enabled: newValue)
                        }
                    
                    // 使用 LabeledContent 或 HStack 对齐
                    HStack {
                        Text("Global Hotkey")
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .toggleWindow)
                    }
                } header: {
                    Text("System")
                }
                
                Section {
                    // 限制历史记录的 Stepper
                    Stepper(value: $historyLimit, in: 0...50) {
                        HStack {
                            Text("History Limit:")
                            Spacer()
                            Text("\(historyLimit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Toggle("Auto-copy Result", isOn: $autoCopy)
                } header: {
                    Text("Behavior")
                }
                Section {
                                    // Python Path
                                    VStack(alignment: .leading) {
                                        Text("Python Interpreter Path")
                                        TextField("/usr/bin/python3", text: $pythonPath)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    
                                    // [新增] Script Directory 设置
                                    VStack(alignment: .leading) {
                                        Text("Script Directory")
                                        HStack {
                                            TextField("Path to your scripts folder", text: $scriptDirectory)
                                                .textFieldStyle(.roundedBorder)
                                            
                                            Button(action: { showFolderImporter = true }) {
                                                Image(systemName: "folder")
                                            }
                                        }
                                        Text("Place bash/zsh scripts here to run them by name via 'run <name>'")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } header: {
                                    Text("Environment")
                                }
                            }
                            .formStyle(.grouped)
                            .tabItem { Label("General", systemImage: "gear") }
                            // 文件导入器逻辑
                            .fileImporter(
                                isPresented: $showFolderImporter,
                                allowedContentTypes: [.folder],
                                allowsMultipleSelection: false
                            ) { result in
                                if let url = try? result.get().first {
                                    // 必须请求安全访问权限
                                    let _ = url.startAccessingSecurityScopedResource()
                                    scriptDirectory = url.path
                                }
                            }
            // --- Tab 2: AI & Network ---
            Form {
                Section(header: Text("Credentials")) {
                    SecureField("API Key", text: $geminiKey)
                    TextField("Model Name", text: $geminiModel)
                    Text("Default: gemini-1.5-flash").font(.caption).foregroundStyle(.secondary)
                }
                
                Section(header: Text("Network")) {
                    // [新增] 代理设置
                    TextField("Proxy URL (Optional)", text: $geminiProxy, prompt: Text("https://your-proxy.com"))
                    Text("Leave empty to use default Google API.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("AI Service", systemImage: "brain.head.profile") }
            
            // --- Tab 3: Command Aliases ---
            Form {
                Section(header: Text("Custom Triggers")) {
                    HStack {
                        Text("Dictionary:")
                        Spacer()
                        TextField("def", text: $aliasDef).frame(width: 80)
                    }
                    HStack {
                        Text("AI Chat:")
                        Spacer()
                        TextField("ask", text: $aliasAsk).frame(width: 80)
                    }
                    HStack {
                        Text("Web Search:")
                        Spacer()
                        TextField("ser", text: $aliasSer).frame(width: 80)
                    }
                    HStack {
                        Text("Python Code:")
                        Spacer()
                        TextField("py", text: $aliasPy).frame(width: 80)
                        }
                }
                
                Section {
                    Text("Tip: Use 'help' command in the main window to see current configuration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Aliases", systemImage: "keyboard") }
        }
        // 调整设置窗口大小，使其看起来更宽敞，并允许适度拉伸
        .frame(width: 500, height: 400)
        .padding()
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
}
