import SwiftUI
import KeyboardShortcuts
import ServiceManagement

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
                                    // Python 路径设置
                                    VStack(alignment: .leading) {
                                        Text("Python Interpreter Path")
                                        TextField("/usr/bin/python3", text: $pythonPath)
                                            .textFieldStyle(.roundedBorder)
                                        Text("Usually `/usr/bin/python3` or `/opt/homebrew/bin/python3`")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                }header:{
                    Text("Environment")
                }
            }
            // 这里使用 .formStyle(.grouped) 让 macOS 自动处理内边距和居中
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gear") }
            
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
        .frame(width: 500, height: 350)
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
