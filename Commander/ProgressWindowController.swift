import AppKit
import SwiftUI
import SwiftTerm
import Darwin
import QuickLookUI

private final class ProgressSurfaceWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ProgressWindowController {
    private weak var appState: AppState?
    private var windows: [UUID: NSWindowController] = [:]
    private var delegates: [UUID: ProgressSurfaceWindowDelegate] = [:]
    private var closingProgrammatically: Set<UUID> = []

    init(appState: AppState) {
        self.appState = appState
    }

    func showSession(_ sessionID: UUID) {
        guard let appState, let session = appState.progressSession(id: sessionID) else { return }

        if let existing = windows[sessionID]?.window {
            existing.title = session.displayTitle
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = ProgressSurfaceRootView(appState: appState, sessionID: sessionID)
        let hostingView = NSHostingView(rootView: rootView)
        let window = ProgressSurfaceWindow(
            contentRect: initialFrame(for: session),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = session.displayTitle
        window.contentView = hostingView
        window.minSize = minimumSize(for: session.presentation)
        window.setContentSize(defaultSize(for: session.presentation))
        window.center()
        window.isReleasedWhenClosed = false

        let delegate = ProgressSurfaceWindowDelegate(sessionID: sessionID, owner: self)
        window.delegate = delegate

        let controller = NSWindowController(window: window)
        windows[sessionID] = controller
        delegates[sessionID] = delegate

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeSession(_ sessionID: UUID) {
        guard let controller = windows.removeValue(forKey: sessionID) else { return }
        delegates.removeValue(forKey: sessionID)
        closingProgrammatically.insert(sessionID)
        controller.close()
        closingProgrammatically.remove(sessionID)
    }

    fileprivate func handleUserClosedWindow(for sessionID: UUID) {
        guard !closingProgrammatically.contains(sessionID) else { return }
        windows.removeValue(forKey: sessionID)
        delegates.removeValue(forKey: sessionID)
        appState?.restoreDetachedProgressSession(sessionID)
    }

    private func defaultSize(for presentation: ProgressPresentation) -> NSSize {
        switch presentation {
        case .terminal:
            return NSSize(width: 780, height: 460)
        case .note, .todo:
            return NSSize(width: 760, height: 520)
        case .image, .file:
            return NSSize(width: 900, height: 640)
        }
    }

    private func minimumSize(for presentation: ProgressPresentation) -> NSSize {
        switch presentation {
        case .terminal:
            return NSSize(width: 520, height: 260)
        case .note, .todo:
            return NSSize(width: 420, height: 260)
        case .image, .file:
            return NSSize(width: 520, height: 360)
        }
    }

    private func initialFrame(for session: ProgressSessionItem) -> NSRect {
        let size = defaultSize(for: session.presentation)
        return NSRect(x: 0, y: 0, width: size.width, height: size.height)
    }
}

private final class ProgressSurfaceWindowDelegate: NSObject, NSWindowDelegate {
    private let sessionID: UUID
    private weak var owner: ProgressWindowController?

    init(sessionID: UUID, owner: ProgressWindowController) {
        self.sessionID = sessionID
        self.owner = owner
    }

    func windowWillClose(_ notification: Notification) {
        owner?.handleUserClosedWindow(for: sessionID)
    }
}

struct ProgressSurfaceRootView: View {
    @Bindable var appState: AppState
    let sessionID: UUID

    var body: some View {
        if let session = appState.progressSession(id: sessionID) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: iconName(for: session.presentation))
                        .foregroundStyle(.secondary)

                    Text(session.displayTitle)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    if session.isRunning {
                        Text("Running")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Button("Return") {
                            appState.attachProgressSession(session.id)
                        }

                        Button("Stop") {
                            appState.stopProgressSession(session.id)
                        }
                    } else {
                        Button("Return") {
                            appState.attachProgressSession(session.id)
                        }

                        Button("Close") {
                            appState.closeProgressSession(session.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()

                ProgressSurfaceContentView(appState: appState, session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 420, minHeight: 220)
        } else {
            Color.clear
        }
    }

    private func iconName(for presentation: ProgressPresentation) -> String {
        switch presentation {
        case .terminal:
            return "terminal"
        case .note:
            return "note.text"
        case .todo:
            return "checkmark.square"
        case .image:
            return "photo"
        case .file:
            return "doc.richtext"
        }
    }
}

private struct ProgressSurfaceContentView: View {
    @Bindable var appState: AppState
    let session: ProgressSessionItem

    var body: some View {
        switch session.presentation {
        case .terminal:
            SwiftTermSessionView(
                sessionID: session.id,
                command: session.command,
                onRegisterTerminator: { id, terminate in
                    appState.registerProgressSessionController(sessionID: id, terminate: terminate)
                },
                onProcessTerminated: { id, exitCode, transcript in
                    appState.completeProgressSession(sessionID: id, exitCode: exitCode, transcript: transcript)
                }
            )
            .padding(10)

        case .note:
            TextEditor(
                text: Binding(
                    get: { appState.noteText(for: session.id) },
                    set: { appState.updateProgressNote(sessionID: session.id, text: $0) }
                )
            )
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(10)

        case .todo:
            TodoSessionView(appState: appState, sessionID: session.id, compact: false)

        case .image:
            ImagePreviewSessionView(path: session.previewPath)

        case .file:
            FilePreviewSessionView(path: session.previewPath)
        }
    }
}

struct TodoSessionView: View {
    @Bindable var appState: AppState
    let sessionID: UUID
    let compact: Bool

    var body: some View {
        let items = appState.todoItems(for: sessionID)
        let completedCount = items.filter(\.isCompleted).count

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(summaryText(itemCount: items.count, completedCount: completedCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if completedCount > 0 {
                    Button("Clear Done") {
                        appState.clearCompletedTodoItems(sessionID: sessionID)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            HStack(spacing: 8) {
                TextField(
                    "Add todo...",
                    text: Binding(
                        get: { appState.todoDraft(for: sessionID) },
                        set: { appState.updateTodoDraft(sessionID: sessionID, text: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    submitDraft()
                }

                Button("Add") {
                    submitDraft()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.todoDraft(for: sessionID).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if items.isEmpty {
                VStack(spacing: 6) {
                    Text("No todos yet.")
                        .foregroundStyle(.secondary)
                    Text("Use `todo <text>` or add one here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            TodoRowView(appState: appState, sessionID: sessionID, item: item)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(compact ? 8 : 12)
    }

    private func submitDraft() {
        appState.addTodoItem(sessionID: sessionID, text: appState.todoDraft(for: sessionID))
    }

    private func summaryText(itemCount: Int, completedCount: Int) -> String {
        if itemCount == 0 {
            return "Empty list"
        }

        let openCount = itemCount - completedCount
        return "\(openCount) open, \(completedCount) done"
    }
}

private struct TodoRowView: View {
    @Bindable var appState: AppState
    let sessionID: UUID
    let item: TodoItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: {
                appState.toggleTodoItem(sessionID: sessionID, itemID: item.id)
            }) {
                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
            }
            .buttonStyle(.borderless)

            TextField(
                "Todo",
                text: Binding(
                    get: { todoText },
                    set: { appState.updateTodoItemText(sessionID: sessionID, itemID: item.id, text: $0) }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .strikethrough(item.isCompleted, color: .secondary)
            .foregroundStyle(item.isCompleted ? .secondary : .primary)

            Button(action: {
                appState.removeTodoItem(sessionID: sessionID, itemID: item.id)
            }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    private var todoText: String {
        appState.todoItems(for: sessionID)
            .first(where: { $0.id == item.id })?
            .text ?? item.text
    }
}

struct ImagePreviewSessionView: View {
    let path: String

    var body: some View {
        if let image = NSImage(contentsOfFile: path) {
            ScrollView([.vertical, .horizontal]) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            }
        } else {
            VStack(spacing: 6) {
                Text("Unable to load image preview.")
                    .foregroundStyle(.secondary)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct FilePreviewSessionView: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.subviews.forEach { $0.removeFromSuperview() }

        let url = URL(fileURLWithPath: path)
        guard let preview = QLPreviewView(frame: nsView.bounds, style: .normal) else {
            let label = NSTextField(labelWithString: "Unable to load file preview.")
            label.textColor = .secondaryLabelColor
            label.frame = nsView.bounds.insetBy(dx: 12, dy: 12)
            label.autoresizingMask = [.width, .height]
            nsView.addSubview(label)
            return
        }
        preview.autoresizingMask = [.width, .height]
        preview.previewItem = url as NSURL
        nsView.addSubview(preview)
    }
}

struct SwiftTermSessionView: NSViewRepresentable {
    let sessionID: UUID
    let command: String
    let onRegisterTerminator: (UUID, @escaping () -> Void) -> Void
    let onProcessTerminated: (UUID, Int32?, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sessionID: sessionID,
            command: command,
            onRegisterTerminator: onRegisterTerminator,
            onProcessTerminated: onProcessTerminated
        )
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.configureNativeColors()
        view.optionAsMetaKey = true
        view.allowMouseReporting = true
        view.caretViewTracksFocus = true
        view.processDelegate = context.coordinator
        context.coordinator.terminalView = view

        let click = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.focusTerminalFromGesture(_:))
        )
        view.addGestureRecognizer(click)
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        context.coordinator.sessionID = sessionID
        context.coordinator.command = command
        context.coordinator.terminalView = nsView
        context.coordinator.startProcessIfNeeded(on: nsView)
        context.coordinator.requestInitialFocusIfNeeded()
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var sessionID: UUID
        var command: String
        private let onRegisterTerminator: (UUID, @escaping () -> Void) -> Void
        private let onProcessTerminated: (UUID, Int32?, String) -> Void
        fileprivate weak var terminalView: LocalProcessTerminalView?
        private var hasRequestedInitialFocus = false
        private var hasStartedProcess = false
        private var hasReportedTermination = false

        init(
            sessionID: UUID,
            command: String,
            onRegisterTerminator: @escaping (UUID, @escaping () -> Void) -> Void,
            onProcessTerminated: @escaping (UUID, Int32?, String) -> Void
        ) {
            self.sessionID = sessionID
            self.command = command
            self.onRegisterTerminator = onRegisterTerminator
            self.onProcessTerminated = onProcessTerminated
        }

        func requestInitialFocusIfNeeded() {
            guard !hasRequestedInitialFocus else { return }
            guard let terminalView else { return }
            guard terminalView.window != nil else { return }
            hasRequestedInitialFocus = true
            terminalView.window?.makeFirstResponder(terminalView)
        }

        @objc
        func focusTerminalFromGesture(_ gesture: NSGestureRecognizer) {
            guard let terminalView else { return }
            terminalView.window?.makeFirstResponder(terminalView)
        }

        func startProcessIfNeeded(on terminal: LocalProcessTerminalView) {
            guard !hasStartedProcess else { return }
            hasStartedProcess = true

            let arguments = ["-lc", command]
            terminal.startProcess(
                executable: "/bin/zsh",
                args: arguments,
                environment: commandEnvironment(),
                currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path
            )

            onRegisterTerminator(sessionID) { [weak terminal] in
                guard let terminal else { return }
                let shellPid = terminal.process.shellPid
                terminal.send(txt: "\u{03}")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    self.terminateProcessTree(shellPid: shellPid)
                    terminal.terminate()
                }
            }
        }

        private func terminateProcessTree(shellPid: pid_t) {
            guard shellPid > 0 else { return }

            if kill(-shellPid, SIGTERM) != 0 {
                _ = kill(shellPid, SIGTERM)
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.45) {
                if kill(-shellPid, 0) == 0 {
                    _ = kill(-shellPid, SIGKILL)
                } else if kill(shellPid, 0) == 0 {
                    _ = kill(shellPid, SIGKILL)
                }
            }
        }

        private func commandEnvironment() -> [String] {
            var list = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
            let env = ProcessInfo.processInfo.environment
            let pathValue = env["PATH"] ?? "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

            list.append("PATH=\(pathValue)")
            list.append("SWIFT_CTX=1")
            if let home = env["HOME"] {
                list.append("HOME=\(home)")
            }
            return list
        }

        private func captureTranscript(from source: TerminalView) -> String {
            let active = String(decoding: source.terminal.getBufferAsData(kind: .active), as: UTF8.self)
            let normal = String(decoding: source.terminal.getBufferAsData(kind: .normal), as: UTF8.self)
            let alt = String(decoding: source.terminal.getBufferAsData(kind: .alt), as: UTF8.self)

            let candidates = [active, normal, alt]
            return candidates.max(by: { $0.count < $1.count }) ?? ""
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            guard !hasReportedTermination else { return }
            hasReportedTermination = true
            let transcript = captureTranscript(from: source)

            DispatchQueue.main.async { [sessionID, onProcessTerminated] in
                onProcessTerminated(sessionID, exitCode, transcript)
            }
        }
    }
}
