import AppKit

final class StatusItemController: NSObject {
    private weak var appState: AppState?
    private weak var statusItem: NSStatusItem?
    private weak var windowController: CommanderWindowController?
    private var isShowingContextMenu = false

    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open Commander", action: #selector(openCommander), keyEquivalent: "")
        openItem.target = self

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self

        let quitItem = NSMenuItem(title: "Quit Commander", action: #selector(quitCommander), keyEquivalent: "q")
        quitItem.target = self

        menu.items = [openItem, settingsItem, .separator(), quitItem]
        return menu
    }()

    func configure(statusItem: NSStatusItem, appState: AppState, windowController: CommanderWindowController) {
        self.statusItem = statusItem
        self.appState = appState
        self.windowController = windowController

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            Task { @MainActor in
                self.appState?.openWindowFromMenu()
            }
            return
        }

        if event.type == .rightMouseUp {
            guard !isShowingContextMenu else { return }
            isShowingContextMenu = true
            let menuOrigin = NSPoint(x: 0, y: sender.bounds.maxY + 4)
            contextMenu.popUp(positioning: nil, at: menuOrigin, in: sender)
            isShowingContextMenu = false
            return
        }

        guard !isShowingContextMenu else { return }
        Task { @MainActor in
            self.windowController?.toggleWindow(anchorButton: sender)
        }
    }

    @objc
    private func openCommander() {
        Task { @MainActor in
            self.windowController?.showWindow(anchorButton: self.statusItem?.button)
        }
    }

    @objc
    private func openSettings() {
        Task { @MainActor in
            self.appState?.openSettingsFromMenu()
        }
    }

    @objc
    private func quitCommander() {
        appState?.quitFromMenu()
    }
}
