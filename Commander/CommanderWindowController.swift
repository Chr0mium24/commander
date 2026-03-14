import AppKit
import SwiftUI

private final class CommanderWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class CommanderWindowController: NSObject, NSWindowDelegate {
    private weak var appState: AppState?
    private var window: CommanderWindow?

    init(appState: AppState) {
        self.appState = appState
    }

    func toggleWindow(anchorButton: NSStatusBarButton? = nil) {
        guard let window else {
            showWindow(anchorButton: anchorButton)
            return
        }
        if window.isVisible {
            hideWindow()
        } else {
            showWindow(anchorButton: anchorButton)
        }
    }

    func showWindow(anchorButton: NSStatusBarButton? = nil) {
        guard let appState else { return }
        let window = ensureWindow(appState: appState)
        positionWindow(window, under: anchorButton)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        appState.isWindowPresented = true
        appState.showHistoryView = false
    }

    func hideWindow() {
        window?.orderOut(nil)
        appState?.isWindowPresented = false
    }

    func windowWillClose(_ notification: Notification) {
        appState?.isWindowPresented = false
    }

    private func ensureWindow(appState: AppState) -> CommanderWindow {
        if let window {
            return window
        }

        let hostingView = NSHostingView(rootView: ContentView(appState: appState))
        let frame = NSRect(x: 0, y: 0, width: 560, height: 520)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        let window = CommanderWindow(
            contentRect: frame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 460, height: 300)
        window.delegate = self
        window.setFrameAutosaveName("CommanderMainWindow")

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        self.window = window
        return window
    }

    private func positionWindow(_ window: NSWindow, under button: NSStatusBarButton?) {
        guard
            let button,
            let buttonWindow = button.window
        else { return }

        let localRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(localRect)
        guard let screen = buttonWindow.screen ?? NSScreen.main else { return }

        var frame = window.frame
        let visible = screen.visibleFrame
        let spacing: CGFloat = 8

        let desiredX = screenRect.midX - (frame.width / 2)
        let maxX = visible.maxX - frame.width
        frame.origin.x = min(max(desiredX, visible.minX), maxX)

        let desiredTop = screenRect.minY - spacing
        frame.origin.y = max(visible.minY, desiredTop - frame.height)

        window.setFrame(frame, display: false)
    }
}
