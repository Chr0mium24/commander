import AppKit

final class StatusItemController: NSObject {
    private weak var appState: AppState?
    private weak var statusItem: NSStatusItem?
    private weak var originalTarget: AnyObject?
    private var originalAction: Selector?

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

    func configure(statusItem: NSStatusItem, appState: AppState) {
        self.statusItem = statusItem
        self.appState = appState

        guard let button = statusItem.button else { return }
        if originalAction == nil {
            originalTarget = button.target as AnyObject?
            originalAction = button.action
        }
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
            statusItem?.popUpMenu(contextMenu)
            return
        }

        if let action = originalAction {
            let target = originalTarget
            _ = NSApp.sendAction(action, to: target, from: sender)
        } else {
            Task { @MainActor in
                self.appState?.openWindowFromMenu()
            }
        }
    }

    @objc
    private func openCommander() {
        Task { @MainActor in
            self.appState?.openWindowFromMenu()
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
