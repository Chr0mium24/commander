import SwiftUI
import MenuBarExtraAccess

@main
struct CommanderApp: App {
    @State private var appState: AppState
    @State private var statusItemController = StatusItemController()
    @State private var windowController: CommanderWindowController

    init() {
        let appState = AppState()
        let windowController = CommanderWindowController(appState: appState)
        appState.windowToggleHandler = { [weak windowController] in
            Task { @MainActor in
                windowController?.toggleWindow()
            }
        }
        appState.windowShowHandler = { [weak windowController] in
            Task { @MainActor in
                windowController?.showWindow()
            }
        }
        appState.windowHideHandler = { [weak windowController] in
            Task { @MainActor in
                windowController?.hideWindow()
            }
        }
        _appState = State(initialValue: appState)
        _windowController = State(initialValue: windowController)
    }
    
    var body: some Scene {
        MenuBarExtra("Commander", systemImage: "terminal") {
            Button("Open Commander") {
                appState.openWindowFromMenu()
            }
            Button("Settings...") {
                appState.openSettingsFromMenu()
            }
            Divider()
            Button("Quit Commander") {
                appState.quitFromMenu()
            }
        }
        .menuBarExtraStyle(.menu)
        .menuBarExtraAccess(isPresented: .constant(false)) { statusItem in
            statusItemController.configure(statusItem: statusItem, appState: appState, windowController: windowController)
        }

        Settings {
            SettingsView()
        }
    }
}
