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
    private let compactHeight: CGFloat = 40

    init(appState: AppState) {
        self.appState = appState
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
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
        let hasOutput = shouldShowOutput(for: appState)
        if !hasOutput {
            applyCompactHeight(on: window, animated: false)
        }
        positionWindow(window, under: anchorButton)
        window.makeKeyAndOrderFront(nil)
        if !hasOutput {
            applyCompactHeight(on: window, animated: false)
        }
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

    func windowDidResignKey(_ notification: Notification) {
        hideWindow()
    }

    func windowDidResignMain(_ notification: Notification) {
        hideWindow()
    }

    @objc
    private func handleApplicationDidResignActive(_ notification: Notification) {
        hideWindow()
    }

    private func ensureWindow(appState: AppState) -> CommanderWindow {
        if let window {
            return window
        }

        let hostingView = NSHostingView(rootView: ContentView(appState: appState))
        let frame = NSRect(x: 0, y: 0, width: 560, height: 520)
        let styleMask: NSWindow.StyleMask = [.borderless, .resizable]
        let window = CommanderWindow(
            contentRect: frame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.level = .normal
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 460, height: compactHeight)
        window.delegate = self
        window.setFrameAutosaveName("CommanderMainWindow")
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 8
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        self.window = window
        return window
    }

    private func positionWindow(_ window: NSWindow, under button: NSStatusBarButton?) {
        guard
            let button,
            let buttonWindow = button.window
        else { return }

        let anchorRect = buttonWindow.frame
        guard let screen = buttonWindow.screen ?? NSScreen.main else { return }

        var frame = window.frame
        let visible = screen.visibleFrame
        let spacing: CGFloat = 6

        let desiredX = anchorRect.midX - (frame.width / 2)
        let maxX = visible.maxX - frame.width
        frame.origin.x = min(max(desiredX, visible.minX), maxX)

        let desiredTop = anchorRect.minY - spacing
        frame.origin.y = max(visible.minY, desiredTop - frame.height)

        window.setFrame(frame, display: false)
    }

    private func shouldShowOutput(for appState: AppState) -> Bool {
        let hasVisibleHistory = appState.showHistoryView && !appState.history.isEmpty
        let hasRunningSession = appState.terminalSessions.contains(where: { $0.isRunning })
        let hasVisibleResult = !sanitizedText(appState.resultText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        return hasVisibleHistory || appState.isLoading || hasRunningSession || hasVisibleResult
    }

    private func sanitizedText(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            if scalar == "\n" || scalar == "\r" || scalar == "\t" {
                return true
            }
            let value = scalar.value
            return !(value < 0x20 || value == 0x7F)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private func applyCompactHeight(on window: NSWindow, animated: Bool) {
        guard abs(window.frame.height - compactHeight) > 1 else { return }

        var frame = window.frame
        frame.origin.y += frame.height - compactHeight
        frame.size.height = compactHeight
        window.setFrame(frame, display: false, animate: animated)
    }
}
