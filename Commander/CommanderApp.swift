import SwiftUI
import MenuBarExtraAccess

@main
struct CommanderApp: App {
    @State private var appState = AppState()
    
    var body: some Scene {
        // 1. 菜单栏入口
        MenuBarExtra("Commander", systemImage: "terminal") {
            ContentView(appState: appState)
        }
        .menuBarExtraStyle(.window) // 设置为 Window 样式
        // 2. 注入 Access 控制
        .menuBarExtraAccess(isPresented: $appState.isWindowPresented) { statusItem in
            // 这里可以进行更底层的 NSStatusItem 配置，例如左键/右键行为微调
        }
        
        // 3. 独立的设置窗口
        Settings {
            SettingsView()
        }
    }
}
