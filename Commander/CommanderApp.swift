import SwiftUI
import MenuBarExtraAccess

@main
struct CommanderApp: App {
    @State private var appState = AppState()
    @State private var statusItemController = StatusItemController()
    
    var body: some Scene {
        MenuBarExtra("Commander", systemImage: "terminal") {
            ContentView(appState: appState)
        }
        .menuBarExtraStyle(.window)
        .menuBarExtraAccess(isPresented: $appState.isWindowPresented) { statusItem in
            statusItemController.configure(statusItem: statusItem, appState: appState)
        }

        Settings {
            SettingsView()
        }
    }
}
