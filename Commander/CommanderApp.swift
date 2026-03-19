import SwiftUI

@main
struct CommanderApp: App {
    @State private var appState: AppState
    @State private var statusItemController = StatusItemController()
    @State private var windowController: CommanderWindowController
    @State private var progressWindowController: ProgressWindowController

    init() {
        let appState = AppState()
        let windowController = CommanderWindowController(appState: appState)
        let progressWindowController = ProgressWindowController(appState: appState)
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
        appState.progressSessionOpenHandler = { [weak progressWindowController] sessionID in
            Task { @MainActor in
                progressWindowController?.showSession(sessionID)
            }
        }
        appState.progressSessionCloseHandler = { [weak progressWindowController] sessionID in
            Task { @MainActor in
                progressWindowController?.closeSession(sessionID)
            }
        }
        statusItemController.setup(appState: appState, windowController: windowController)
        _appState = State(initialValue: appState)
        _statusItemController = State(initialValue: statusItemController)
        _windowController = State(initialValue: windowController)
        _progressWindowController = State(initialValue: progressWindowController)
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
