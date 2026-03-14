import SwiftUI

@main
struct CommanderApp: App {
    @State private var appState: AppState
    @State private var statusItemController = StatusItemController()
    @State private var windowController: CommanderWindowController

    init() {
        let appState = AppState()
        let windowController = CommanderWindowController(appState: appState)
        let statusItemController = StatusItemController()
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
        statusItemController.setup(appState: appState, windowController: windowController)
        _appState = State(initialValue: appState)
        _statusItemController = State(initialValue: statusItemController)
        _windowController = State(initialValue: windowController)
    }
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandMenu("Commander") {
                Button("Previous Command") {
                    appState.restorePreviousCommandResult()
                }
                .keyboardShortcut("z", modifiers: [.command, .option])

                Button("Next Command") {
                    appState.restoreNextCommandResult()
                }
                .keyboardShortcut("z", modifiers: [.command, .option, .shift])
            }
        }
    }
}
