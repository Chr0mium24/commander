import SwiftUI
import MarkdownUI
import Splash
import AppKit
internal import UniformTypeIdentifiers
import QuickLookUI
import WebKit
import OSLog

private let markdownRenderLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "cr.commander",
    category: "MarkdownRender"
)

struct ContentView: View {
    private enum InputFocusField: Hashable {
        case singleLine
        case multiLine
    }

    @Bindable var appState: AppState
    @FocusState private var focusedInput: InputFocusField?
    @State private var multilineInput = false
    @State private var inputText: String = ""
    @State private var inputHistoryCursor: Int?
    @State private var inputHistoryDraft: String = ""
    @State private var isApplyingInputHistoryNavigation = false
    @State private var processBaseHeight: CGFloat = 190
    @GestureState private var processDragTranslation: CGFloat = 0
    @Environment(\.openSettings) private var openSettings
    // 1. 引入环境变量监听当前的系统外观模式 (Dark/Light)
    @Environment(\.colorScheme) private var colorScheme
    
    private let singleLinePlaceholder = "Type 'help'..."
    private let multilinePlaceholderTop: CGFloat = 4
    private let multilinePlaceholderLeading: CGFloat = 4

    private var attachmentStripHeight: CGFloat {
        appState.inputAttachments.isEmpty ? 0 : 40
    }

    private var multilineEditorHeight: CGFloat {
        appState.inputAttachments.isEmpty ? 96 : 132
    }

    private var compactWindowHeight: CGFloat {
        if multilineInput {
            return multilineEditorHeight + attachmentStripHeight + 28
        }
        return 40 + attachmentStripHeight
    }

    private var expandedWindowMinimumHeight: CGFloat {
        220 + attachmentStripHeight + (multilineInput ? 40 : 0)
    }

    private var processMaxHeight: CGFloat {
        420
    }

    private var processHeight: CGFloat {
        min(max(120, processBaseHeight + processDragTranslation), processMaxHeight)
    }

    private var visibleEmbeddedProgressSessions: [ProgressSessionItem] {
        appState.progressSessions.filter { !$0.isDetached }
    }
    
    private var inputHistoryQueries: [String] {
        appState.history
            .map(\.query)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var sanitizedResultText: String {
        let scalars = appState.resultText.unicodeScalars.filter { scalar in
            if scalar == "\n" || scalar == "\r" || scalar == "\t" {
                return true
            }
            let value = scalar.value
            return !(value < 0x20 || value == 0x7F)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private var hasVisibleResultText: Bool {
        !sanitizedResultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasVisibleHistory: Bool {
        appState.showHistoryView && !appState.history.isEmpty
    }

    private var shouldShowOutputSection: Bool {
        hasVisibleHistory || !visibleEmbeddedProgressSessions.isEmpty || appState.isLoading || hasVisibleResultText
    }

    private var shouldShowCopyMarkdownButton: Bool {
        appState.isAIResponse && !appState.isLoading && !appState.resultText.isEmpty
    }

    private var glassBackground: some View {
        ZStack {
            Rectangle()
                .fill(.thickMaterial)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.28),
                    Color.black.opacity(0.16),
                    Color.black.opacity(0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .blendMode(.screen)
        }
    }
    
    var body: some View {
        Group {
            if shouldShowOutputSection {
                VStack(spacing: 0) {
                    inputSection
                    outputSection
                }
                .frame(
                    minWidth: 500,
                    maxWidth: .infinity,
                    minHeight: expandedWindowMinimumHeight,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
            } else {
                inputSection
                    .frame(
                        minWidth: 500,
                        maxWidth: .infinity,
                        minHeight: compactWindowHeight,
                        maxHeight: compactWindowHeight,
                        alignment: .leading
                    )
            }
        }
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            if !shouldShowOutputSection {
                multilineInput = false
            }
            inputText = appState.query
            focusCurrentInput()
            syncWindowHeightWithState(animated: false)
        }
        .onChange(of: inputText) { _, newValue in
            if !isApplyingInputHistoryNavigation, inputHistoryCursor != nil {
                inputHistoryCursor = nil
                inputHistoryDraft = ""
            }
            guard !multilineInput else { return }
            if newValue.contains("\n") || newValue.contains("\r") {
                multilineInput = true
                focusCurrentInput()
            }
        }
        .onChange(of: appState.query) { _, newValue in
            if newValue != inputText {
                inputText = newValue
            }
        }
        .onChange(of: appState.isWindowPresented) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusCurrentInput()
                }
            }
        }
        .onChange(of: shouldShowOutputSection) { _, newValue in
            if !newValue {
                multilineInput = false
                focusCurrentInput()
            }
            syncWindowHeightWithState(animated: true)
        }
        .onChange(of: multilineInput) { _, _ in
            syncWindowHeightWithState(animated: true)
        }
        .onChange(of: appState.shouldOpenSettings) { _, newValue in
            if newValue {
                openSettings()
                appState.shouldOpenSettings = false
            }
        }
        .onChange(of: appState.inputAttachments.count) { _, _ in
            syncWindowHeightWithState(animated: true)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: appState.inputAttachments.isEmpty ? 0 : 8) {
            HStack(alignment: multilineInput ? .top : .center, spacing: 10) {
                Image(systemName: "terminal")
                    .foregroundColor(.secondary)

                if multilineInput {
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text(singleLinePlaceholder)
                                .foregroundStyle(.secondary)
                                .padding(.top, multilinePlaceholderTop)
                                .padding(.leading, multilinePlaceholderLeading)
                        }

                        TextEditor(text: $inputText)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .focused($focusedInput, equals: .multiLine)
                            .onKeyPress(phases: [.down]) { keyPress in
                                handleInputPasteKeyPress(keyPress)
                            }
                            .onExitCommand {
                                handleMultilineExitCommand()
                            }
                    }
                    .frame(minHeight: multilineEditorHeight, maxHeight: multilineEditorHeight)
                } else {
                    TextField(singleLinePlaceholder, text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .frame(height: 22)
                        .focused($focusedInput, equals: .singleLine)
                        .onKeyPress(phases: [.down]) { keyPress in
                            handleInputPasteKeyPress(keyPress)
                        }
                        .onKeyPress(.return, phases: [.down]) { keyPress in
                            if keyPress.modifiers.contains(.shift) {
                                enterMultilineModeWithNewline()
                                return .handled
                            }
                            return .ignored
                        }
                        .onSubmit {
                            submitInput()
                        }
                        .onMoveCommand { direction in
                            switch direction {
                            case .up:
                                browseInputHistoryBackward()
                            case .down:
                                browseInputHistoryForward()
                            default:
                                break
                            }
                        }
                        .onExitCommand {
                            handleExitCommand()
                        }
                }

                HStack(spacing: 8) {
                    Button(action: {
                        pickInputFiles()
                    }) {
                        Image(systemName: appState.inputAttachments.isEmpty ? "doc.badge.plus" : "paperclip")
                    }
                    .buttonStyle(.borderless)
                    .help("Attach files")

                    Button(action: {
                        if multilineInput {
                            multilineInput = false
                            inputText = inputText
                                .replacingOccurrences(of: "\r\n", with: " ")
                                .replacingOccurrences(of: "\n", with: " ")
                        } else {
                            multilineInput = true
                        }
                        focusCurrentInput()
                    }) {
                        Image(systemName: multilineInput ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    }
                    .buttonStyle(.borderless)
                    .help(multilineInput ? "Switch to single-line input" : "Switch to multi-line input")

                    Button(action: {
                        submitInput()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .help(multilineInput ? "Send (Cmd+Enter)" : "Send")
                    .keyboardShortcut(.return, modifiers: [.command])
                }

                if appState.isLoading {
                    ProgressView().controlSize(.small)
                }

                if appState.isLoading {
                    Button(action: {
                        appState.stopCurrentTask()
                    }) {
                        Image(systemName: "stop.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Stop current task")
                }
            }

            if !appState.inputAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appState.inputAttachments) { attachment in
                            HStack(spacing: 6) {
                                Image(systemName: attachment.kind == .image ? "photo" : "doc")
                                    .foregroundStyle(.secondary)
                                Text(attachment.filename)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button(action: {
                                    appState.removeInputAttachment(path: attachment.path)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                appState.selectedAttachmentPath == attachment.path
                                    ? Color.accentColor.opacity(0.22)
                                    : Color.primary.opacity(0.08)
                            )
                            .clipShape(Capsule())
                            .onTapGesture {
                                appState.selectAttachment(path: attachment.path)
                                AttachmentQuickLookController.shared.preview(path: attachment.path)
                            }
                        }

                        Button("Clear") {
                            appState.clearInputAttachments()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, shouldShowOutputSection ? (multilineInput ? 10 : 6) : 3)
        .background(shouldShowOutputSection ? Color.primary.opacity(0.05) : .clear)
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            VStack(alignment: .leading, spacing: 0) {
                if appState.showHistoryView {
                    HistoryView(appState: appState)
                } else {
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if !appState.resultText.isEmpty || (appState.isLoading && appState.resultText == "Thinking...") {
                                    if appState.isLoading && appState.resultText == "Thinking..." {
                                        Text(appState.resultText)
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 4)
                                    } else if !appState.resultText.isEmpty {
                                        if appState.isStreamingMarkdownActive {
                                            StreamingMarkdownResultView(
                                                committedMarkdown: appState.streamingMarkdownSnapshot,
                                                pendingText: appState.streamingMarkdownTail,
                                                colorScheme: colorScheme,
                                                onCopyCode: { code in
                                                    appState.copyToClipboard(code)
                                                },
                                                onRunCode: { language, code in
                                                    appState.runGeneratedCode(language: language, code: code)
                                                },
                                                onEditCode: { language, code in
                                                    appState.openCodeEditor(language: language, code: code)
                                                }
                                            )
                                        } else {
                                            MarkdownResultView(
                                                resultText: appState.resultText,
                                                colorScheme: colorScheme,
                                                onCopyCode: { code in
                                                    appState.copyToClipboard(code)
                                                },
                                                onRunCode: { language, code in
                                                    appState.runGeneratedCode(language: language, code: code)
                                                },
                                                onEditCode: { language, code in
                                                    appState.openCodeEditor(language: language, code: code)
                                                }
                                            )
                                        }
                                    }
                                }

                                if shouldShowCopyMarkdownButton {
                                    HStack {
                                        Spacer()
                                        Button(action: {
                                            appState.copyToClipboard(appState.resultText)
                                        }) {
                                            Image(systemName: "doc.on.doc")
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Copy Markdown")
                                    }
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !visibleEmbeddedProgressSessions.isEmpty {
                            Divider()

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Spacer()
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.35))
                                        .frame(width: 42, height: 5)
                                    Spacer()
                                }
                                .frame(height: 12)
                                .padding(.top, 2)
                                .contentShape(Rectangle())
                                .highPriorityGesture(processResizeGesture())

                                Text("Processes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)

                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 10) {
                                        ForEach(visibleEmbeddedProgressSessions) { session in
                                            progressSessionCard(session)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 12)
                                }
                            }
                            .frame(height: processHeight)
                            .background(Color.primary.opacity(0.03))
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
    
    private func submitInput() {
        let normalized = multilineInput
            ? inputText
            : inputText
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
        let trimmedNormalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedInput = trimmedNormalized.isEmpty && !appState.imageAttachmentPathsForAI().isEmpty
            ? "Describe the attached image."
            : normalized

        appState.query = resolvedInput
        inputText = resolvedInput
        inputHistoryCursor = nil
        inputHistoryDraft = ""
        appState.clearCommandHistoryNavigation()
        appState.executeCommand()
    }

    private func pickInputFiles() {
        let panel = NSOpenPanel()
        panel.title = "Attach Files"
        panel.message = "Selected files will be available to commands and plugins. Image files are also sent with built-in AI requests."
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            appState.addInputAttachments(panel.urls.compactMap(makeInputAttachment))
        }
    }

    private func handleInputPasteKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let characters = keyPress.characters.lowercased()

        if keyPress.modifiers.contains(.command), characters == "v" {
            return pasteAttachmentsFromPasteboard() ? .handled : .ignored
        }

        return .ignored
    }

    private func pasteAttachmentsFromPasteboard() -> Bool {
        let pasteboard = NSPasteboard.general
        var attachments: [InputAttachment] = []

        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            attachments.append(contentsOf: fileURLs.compactMap(makeInputAttachment))
        }

        if attachments.isEmpty,
           let image = NSImage(pasteboard: pasteboard),
           let tempURL = writePastedImageToTemporaryFile(image) {
            attachments.append(
                InputAttachment(
                    path: tempURL.path,
                    kind: .image,
                    mimeType: "image/png"
                )
            )
        }

        guard !attachments.isEmpty else { return false }
        appState.addInputAttachments(attachments)
        focusCurrentInput()
        return true
    }

    private func makeInputAttachment(url: URL) -> InputAttachment? {
        let resolvedURL = url.standardizedFileURL
        let path = resolvedURL.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let mimeType = inferMimeType(for: resolvedURL)
        let kind: InputAttachmentKind = mimeType.hasPrefix("image/") ? .image : .file
        return InputAttachment(path: path, kind: kind, mimeType: mimeType)
    }

    private func inferMimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }
        return "application/octet-stream"
    }

    private func writePastedImageToTemporaryFile(_ image: NSImage) -> URL? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommanderAttachments", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
            try pngData.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private func handleExitCommand() {
        if !visibleEmbeddedProgressSessions.isEmpty {
            if multilineInput {
                collapseToSingleLine()
            } else {
                inputText = ""
                appState.query = ""
            }
            inputHistoryCursor = nil
            inputHistoryDraft = ""
            focusCurrentInput()
            return
        }

        if shouldShowOutputSection {
            appState.collapseToInputOnly()
            inputText = ""
        } else {
            appState.query = inputText
            appState.reset()
            inputText = appState.query
        }
        multilineInput = false
        inputHistoryCursor = nil
        inputHistoryDraft = ""
        focusCurrentInput()
    }

    private func handleMultilineExitCommand() {
        if shouldCollapseToSingleLine() {
            collapseToSingleLine()
            return
        }
        handleExitCommand()
    }

    private func enterMultilineModeWithNewline() {
        if !multilineInput {
            multilineInput = true
        }
        inputText += "\n"
        focusCurrentInput()
    }

    private func shouldCollapseToSingleLine() -> Bool {
        let normalized = inputText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard let lastLine = lines.last else { return true }
        return lastLine.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func collapseToSingleLine() {
        multilineInput = false
        inputText = inputText
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        focusCurrentInput()
    }

    private func browseInputHistoryBackward() {
        guard !inputHistoryQueries.isEmpty else { return }

        if inputHistoryCursor == nil {
            guard inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            inputHistoryDraft = inputText
            inputHistoryCursor = 0
        } else if let cursor = inputHistoryCursor, cursor < inputHistoryQueries.count - 1 {
            inputHistoryCursor = cursor + 1
        }

        guard let cursor = inputHistoryCursor else { return }
        applyInputHistoryQuery(inputHistoryQueries[cursor])
    }

    private func browseInputHistoryForward() {
        guard let cursor = inputHistoryCursor else { return }

        if cursor > 0 {
            inputHistoryCursor = cursor - 1
            if let next = inputHistoryCursor {
                applyInputHistoryQuery(inputHistoryQueries[next])
            }
            return
        }

        inputHistoryCursor = nil
        applyInputHistoryQuery(inputHistoryDraft)
    }

    private func applyInputHistoryQuery(_ value: String) {
        isApplyingInputHistoryNavigation = true
        inputText = value
        appState.query = value
        appState.resultText = ""
        appState.isAIResponse = false
        appState.showHistoryView = false
        appState.clearCommandHistoryNavigation()
        multilineInput = value.contains("\n") || value.contains("\r")
        isApplyingInputHistoryNavigation = false
        focusCurrentInput()
    }

    private func focusCurrentInput() {
        DispatchQueue.main.async {
            focusedInput = multilineInput ? .multiLine : .singleLine
        }
    }

    private func syncWindowHeightWithState(animated: Bool) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }

        var frame = window.frame

        if !shouldShowOutputSection {
            guard abs(frame.height - compactWindowHeight) > 1 else { return }
            frame.origin.y += frame.height - compactWindowHeight
            frame.size.height = compactWindowHeight
            window.setFrame(frame, display: true, animate: animated)
            return
        }

        guard frame.height < expandedWindowMinimumHeight else { return }
        frame.origin.y += frame.height - expandedWindowMinimumHeight
        frame.size.height = expandedWindowMinimumHeight
        window.setFrame(frame, display: true, animate: animated)
    }

    private func processResizeGesture() -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($processDragTranslation) { value, state, _ in
                state = -value.translation.height
            }
            .onEnded { value in
                processBaseHeight = min(max(120, processBaseHeight - value.translation.height), processMaxHeight)
            }
    }

    private func isRunnableCodeLanguage(_ language: String) -> Bool {
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["python", "py", "bash", "sh", "zsh", "shell"].contains(normalized)
    }

    @ViewBuilder
    private func progressSessionCard(_ session: ProgressSessionItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: {
                    appState.toggleProgressSessionCollapsed(session.id)
                }) {
                    Image(systemName: session.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Image(systemName: progressIconName(for: session.presentation))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(session.displayTitle)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(progressStatusText(for: session))
                    .font(.caption2)
                    .foregroundStyle(session.isRunning ? .orange : .secondary)

                Button("Open") {
                    appState.detachProgressSession(session.id)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)

                if session.isRunning {
                    Button("Stop") {
                        appState.stopProgressSession(session.id)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Close") {
                        appState.closeProgressSession(session.id)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if !session.isCollapsed {
                Divider()
                progressSessionContent(session)
            }
        }
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func progressSessionContent(_ session: ProgressSessionItem) -> some View {
        switch session.presentation {
        case .terminal:
            SwiftTermSessionView(
                sessionID: session.id,
                command: session.command,
                currentDirectory: session.currentDirectory,
                onRegisterTerminator: { id, terminate in
                    appState.registerProgressSessionController(sessionID: id, terminate: terminate)
                },
                onProcessTerminated: { id, exitCode, transcript in
                    appState.completeProgressSession(sessionID: id, exitCode: exitCode, transcript: transcript)
                }
            )
            .frame(height: 170)
            .clipped()

        case .note:
            TextEditor(
                text: Binding(
                    get: { appState.noteText(for: session.id) },
                    set: { appState.updateProgressNote(sessionID: session.id, text: $0) }
                )
            )
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(height: 190)

        case .todo:
            TodoSessionView(appState: appState, sessionID: session.id, compact: true)
                .frame(height: 220)

        case .code:
            Text("Open to edit")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)

        case .image:
            ImagePreviewSessionView(path: session.previewPath)
                .frame(height: 220)

        case .file:
            FilePreviewSessionView(path: session.previewPath)
                .frame(height: 220)
        }
    }

    private func progressIconName(for presentation: ProgressPresentation) -> String {
        switch presentation {
        case .terminal:
            return "terminal"
        case .note:
            return "note.text"
        case .todo:
            return "checkmark.square"
        case .code:
            return "curlybraces.square"
        case .image:
            return "photo"
        case .file:
            return "doc.richtext"
        }
    }

    private func progressStatusText(for session: ProgressSessionItem) -> String {
        if session.isRunning {
            return "Running"
        }

        switch session.presentation {
        case .note, .todo:
            if session.presentation == .todo {
                let completed = session.todoItems.filter(\.isCompleted).count
                let open = session.todoItems.count - completed
                if session.todoItems.isEmpty {
                    return "Empty"
                }
                if completed == 0 {
                    return "\(open) open"
                }
                return "\(open) open / \(completed) done"
            }
            return "Editable"
        case .code:
            return session.codeLanguage.isEmpty ? "Editor" : session.codeLanguage.uppercased()
        default:
            return "Ready"
        }
    }
}

private final class AttachmentQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = AttachmentQuickLookController()

    private var items: [NSURL] = []

    func preview(path: String) {
        items = [NSURL(fileURLWithPath: path)]
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        items[index]
    }
}

private struct DetectedCodeBlock: Identifiable {
    let id: Int
    let language: String
    let code: String
}

private enum MarkdownCodeBlockExtractor {
    private static let pattern = "```([A-Za-z0-9_+-]*)[ \\t]*\\n([\\s\\S]*?)\\n?```"

    static func extract(from markdown: String) -> [DetectedCodeBlock] {
        guard !markdown.isEmpty else { return [] }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let fullRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let matches = regex.matches(in: markdown, options: [], range: fullRange)
        var blocks: [DetectedCodeBlock] = []
        blocks.reserveCapacity(matches.count)

        for (index, match) in matches.enumerated() {
            guard
                let langRange = Range(match.range(at: 1), in: markdown),
                let codeRange = Range(match.range(at: 2), in: markdown)
            else {
                continue
            }

            let language = String(markdown[langRange]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let code = String(markdown[codeRange]).trimmingCharacters(in: .newlines)
            if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            blocks.append(
                DetectedCodeBlock(
                    id: index,
                    language: language,
                    code: code
                )
            )
        }

        return blocks
    }
}

private struct MarkdownRenderSegment: Identifiable {
    enum Kind {
        case markdown(String)
        case math(String)
    }

    let id: Int
    let kind: Kind
}

private enum MarkdownFormulaExtractor {
    private enum InlineMathSegment {
        case markdown(String)
        case math(String)
    }

    static func extract(from markdown: String) -> [MarkdownRenderSegment] {
        guard markdown.contains("$$") else {
            return [MarkdownRenderSegment(id: 0, kind: .markdown(markdown))]
        }

        let lines = markdown.components(separatedBy: .newlines)
        var segments: [MarkdownRenderSegment] = []
        var markdownLines: [String] = []
        var formulaLines: [String] = []
        var inCodeFence = false
        var inFormula = false
        var nextID = 0

        func appendMarkdownIfNeeded() {
            guard !markdownLines.isEmpty else { return }
            let text = markdownLines.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(MarkdownRenderSegment(id: nextID, kind: .markdown(text)))
                nextID += 1
            }
            markdownLines.removeAll(keepingCapacity: true)
        }

        func appendFormulaIfNeeded() {
            let text = formulaLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                segments.append(MarkdownRenderSegment(id: nextID, kind: .math(text)))
                nextID += 1
            }
            formulaLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if !inFormula, trimmed.hasPrefix("```") {
                inCodeFence.toggle()
                markdownLines.append(line)
                continue
            }

            if !inCodeFence {
                if !inFormula, let inlineSegments = inlineBlockMathSegments(from: line) {
                    appendMarkdownIfNeeded()
                    for segment in inlineSegments {
                        switch segment {
                        case .markdown(let text):
                            segments.append(MarkdownRenderSegment(id: nextID, kind: .markdown(text)))
                            nextID += 1
                        case .math(let formula):
                            segments.append(MarkdownRenderSegment(id: nextID, kind: .math(formula)))
                            nextID += 1
                        }
                    }
                    continue
                }

                if !inFormula,
                   trimmed.hasPrefix("$$"),
                   trimmed.hasSuffix("$$"),
                   trimmed.count > 4 {
                    appendMarkdownIfNeeded()
                    let formula = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !formula.isEmpty {
                        segments.append(MarkdownRenderSegment(id: nextID, kind: .math(formula)))
                        nextID += 1
                    }
                    continue
                }

                if trimmed == "$$" {
                    if inFormula {
                        appendFormulaIfNeeded()
                    } else {
                        appendMarkdownIfNeeded()
                    }
                    inFormula.toggle()
                    continue
                }
            }

            if inFormula {
                formulaLines.append(line)
            } else {
                markdownLines.append(line)
            }
        }

        if inFormula {
            markdownRenderLogger.warning("Unclosed block math delimiter detected while extracting markdown formula segments")
            markdownLines.append("$$")
            markdownLines.append(contentsOf: formulaLines)
        }
        appendMarkdownIfNeeded()

        if segments.isEmpty {
            return [MarkdownRenderSegment(id: 0, kind: .markdown(markdown))]
        }
        return segments
    }

    private static func inlineBlockMathSegments(from line: String) -> [InlineMathSegment]? {
        guard line.contains("$$") else { return nil }
        var cursor = line.startIndex
        var producedMath = false
        var parsedSegments: [InlineMathSegment] = []

        while let open = line[cursor...].range(of: "$$") {
            let prefix = String(line[cursor..<open.lowerBound])
            if !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parsedSegments.append(.markdown(prefix))
            }

            guard let close = line[open.upperBound...].range(of: "$$") else {
                markdownRenderLogger.warning("Inline block math has opening '$$' without closing delimiter; fallback to plain markdown line")
                return nil
            }

            let formula = String(line[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !formula.isEmpty {
                parsedSegments.append(.math(formula))
                producedMath = true
            }

            cursor = close.upperBound
        }

        let suffix = String(line[cursor...])
        if !suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parsedSegments.append(.markdown(suffix))
        }

        return producedMath ? parsedSegments : nil
    }
}

private struct MarkdownResultView: View {
    let resultText: String
    let colorScheme: ColorScheme
    let onCopyCode: (String) -> Void
    let onRunCode: (String, String) -> Void
    let onEditCode: (String, String) -> Void

    private var renderSegments: [MarkdownRenderSegment] {
        MarkdownFormulaExtractor.extract(from: resultText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(renderSegments) { segment in
                segmentView(segment)
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: MarkdownRenderSegment) -> some View {
        switch segment.kind {
        case .markdown(let markdown):
            Markdown(markdown)
                .markdownBlockStyle(\.codeBlock) { configuration in
                    codeBlock(configuration)
                }
                .markdownBlockStyle(\.paragraph) { configuration in
                    paragraphBlock(configuration)
                }
                .markdownTheme(.adaptiveTheme(colorScheme: colorScheme))
                .markdownCodeSyntaxHighlighter(
                    colorScheme == .dark
                        ? SplashCodeSyntaxHighlighter.wwdc17
                        : SplashCodeSyntaxHighlighter.basicLight
                )
                .textSelection(.enabled)
                .id(markdown)

        case .math(let latex):
            MathFormulaView(latex: latex, colorScheme: colorScheme)
                .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func codeBlock(_ configuration: CodeBlockConfiguration) -> some View {
        let language = normalizedLanguage(from: configuration.language)
        let runnable = isRunnableCodeLanguage(language)

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    onCopyCode(configuration.content)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Copy code")

                Button {
                    onEditCode(language, configuration.content)
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Edit code")

                if runnable {
                    Button {
                        onRunCode(language, configuration.content)
                    } label: {
                        Label("Run", systemImage: "play.fill")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .help("Run code")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05))
            .textSelection(.disabled)

            Divider()

            ScrollView(.horizontal) {
                configuration.label
                    .relativeLineSpacing(.em(0.25))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.9))
                    }
                    .padding(10)
            }
        }
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .markdownMargin(top: .zero, bottom: .em(0.9))
    }

    @ViewBuilder
    private func paragraphBlock(_ configuration: BlockConfiguration) -> some View {
        let markdown = configuration.content.renderMarkdown().trimmingCharacters(in: .whitespacesAndNewlines)
        if containsInlineFormula(in: markdown) {
            InlineMathParagraphView(markdown: markdown, colorScheme: colorScheme)
                .markdownMargin(top: .zero, bottom: .em(1))
        } else {
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: .zero, bottom: .em(1))
        }
    }

    private func normalizedLanguage(from fenceInfo: String?) -> String {
        guard let raw = fenceInfo?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ""
        }
        let token = raw.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? raw
        return token.lowercased()
    }

    private func isRunnableCodeLanguage(_ language: String) -> Bool {
        ["python", "py", "bash", "sh", "zsh", "shell"].contains(language)
    }

    private func containsInlineFormula(in markdown: String) -> Bool {
        guard markdown.contains("$") else { return false }
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\\)\$(?!\$)(.+?)(?<!\\)\$(?!\$)"#, options: []) else {
            return false
        }
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        return regex.firstMatch(in: markdown, options: [], range: range) != nil
    }
}

private struct StreamingMarkdownResultView: View {
    let committedMarkdown: String
    let pendingText: String
    let colorScheme: ColorScheme
    let onCopyCode: (String) -> Void
    let onRunCode: (String, String) -> Void
    let onEditCode: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !committedMarkdown.isEmpty {
                MarkdownResultView(
                    resultText: committedMarkdown,
                    colorScheme: colorScheme,
                    onCopyCode: onCopyCode,
                    onRunCode: onRunCode,
                    onEditCode: onEditCode
                )
            }

            if !pendingText.isEmpty {
                Text(verbatim: pendingText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct MathFormulaView: View {
    let latex: String
    let colorScheme: ColorScheme

    @State private var contentHeight: CGFloat = 56

    private var formulaTextHex: String {
        colorScheme == .dark ? "#E6E2EA" : "#202124"
    }

    var body: some View {
        MathFormulaWebView(
            latex: latex,
            textHex: formulaTextHex,
            contentHeight: $contentHeight
        )
        .frame(height: min(max(contentHeight, 44), 260))
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct InlineMathParagraphView: View {
    let markdown: String
    let colorScheme: ColorScheme
    @State private var contentHeight: CGFloat = 28

    private var textHex: String {
        colorScheme == .dark ? "#E6E2EA" : "#202124"
    }

    var body: some View {
        InlineMathWebView(
            markdown: markdown,
            textHex: textHex,
            contentHeight: $contentHeight
        )
        .frame(height: min(max(contentHeight, 22), 260))
    }
}

private final class PassthroughWKWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct MathFormulaWebView: NSViewRepresentable {
    let latex: String
    let textHex: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> PassthroughWKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = PassthroughWKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.allowsBackForwardNavigationGestures = false
        return view
    }

    func updateNSView(_ nsView: PassthroughWKWebView, context: Context) {
        guard context.coordinator.lastLatex != latex || context.coordinator.lastTextHex != textHex else { return }
        context.coordinator.lastLatex = latex
        context.coordinator.lastTextHex = textHex
        nsView.loadHTMLString(Self.html(for: latex, textHex: textHex), baseURL: URL(string: "https://cdn.jsdelivr.net"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLatex: String = ""
        var lastTextHex: String = ""
        @Binding var contentHeight: CGFloat

        init(contentHeight: Binding<CGFloat>) {
            _contentHeight = contentHeight
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateHeight(for: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.updateHeight(for: webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            markdownRenderLogger.error("MathFormulaWebView navigation failed: \(error.localizedDescription, privacy: .public)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            markdownRenderLogger.error("MathFormulaWebView provisional navigation failed: \(error.localizedDescription, privacy: .public)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            markdownRenderLogger.error("MathFormulaWebView web content process terminated; reloading")
            webView.reload()
        }

        private func updateHeight(for webView: WKWebView) {
            let script = "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, document.getElementById('math')?.scrollHeight || 0)"
            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self else { return }
                if let error {
                    markdownRenderLogger.error("MathFormulaWebView evaluateJavaScript failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
                guard let number = result as? NSNumber else { return }
                let newHeight = CGFloat(truncating: number) + 2
                guard newHeight.isFinite, newHeight > 0 else { return }
                DispatchQueue.main.async {
                    if abs(self.contentHeight - newHeight) > 0.5 {
                        self.contentHeight = newHeight
                    }
                }
            }
        }
    }

    private static func html(for latex: String, textHex: String) -> String {
        let escaped = htmlEscape("$$\(latex)$$")
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
          <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
          <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"></script>
          <style>
            html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; }
            body { font-size: 1.05rem; color: \(textHex); -webkit-user-select: none; cursor: default; }
            #math { padding: 8px 10px 10px 10px; }
            #math .katex, #math .katex-display { color: \(textHex) !important; }
            #math .katex-display { margin: 0.15em 0; }
          </style>
        </head>
        <body>
          <div id="math">\(escaped)</div>
          <script>
            document.addEventListener("DOMContentLoaded", function () {
              if (window.renderMathInElement) {
                renderMathInElement(document.body, {
                  delimiters: [{ left: "$$", right: "$$", display: true }],
                  throwOnError: false
                });
              }
            });
          </script>
        </body>
        </html>
        """
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

private struct InlineMathWebView: NSViewRepresentable {
    let markdown: String
    let textHex: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> PassthroughWKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = PassthroughWKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ nsView: PassthroughWKWebView, context: Context) {
        guard context.coordinator.lastMarkdown != markdown || context.coordinator.lastTextHex != textHex else { return }
        context.coordinator.lastMarkdown = markdown
        context.coordinator.lastTextHex = textHex
        nsView.loadHTMLString(Self.html(for: markdown, textHex: textHex), baseURL: URL(string: "https://cdn.jsdelivr.net"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastMarkdown: String = ""
        var lastTextHex: String = ""
        @Binding var contentHeight: CGFloat

        init(contentHeight: Binding<CGFloat>) {
            _contentHeight = contentHeight
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateHeight(for: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.updateHeight(for: webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            markdownRenderLogger.error("InlineMathWebView navigation failed: \(error.localizedDescription, privacy: .public)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            markdownRenderLogger.error("InlineMathWebView provisional navigation failed: \(error.localizedDescription, privacy: .public)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            markdownRenderLogger.error("InlineMathWebView web content process terminated; reloading")
            webView.reload()
        }

        private func updateHeight(for webView: WKWebView) {
            let script = "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, document.getElementById('content')?.scrollHeight || 0)"
            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self else { return }
                if let error {
                    markdownRenderLogger.error("InlineMathWebView evaluateJavaScript failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
                guard let number = result as? NSNumber else { return }
                let newHeight = CGFloat(truncating: number) + 2
                guard newHeight.isFinite, newHeight > 0 else { return }
                DispatchQueue.main.async {
                    if abs(self.contentHeight - newHeight) > 0.5 {
                        self.contentHeight = newHeight
                    }
                }
            }
        }
    }

    private static func html(for markdown: String, textHex: String) -> String {
        let escaped = htmlEscape(markdown)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
          <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
          <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"></script>
          <script defer src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
          <style>
            html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; }
            body { font-size: 0.98rem; color: \(textHex); -webkit-user-select: none; cursor: default; }
            #content { padding: 0; margin: 0; }
            #content p { margin: 0 0 0.9em 0; }
            #content p:last-child { margin-bottom: 0; }
            #content .katex, #content .katex-display { color: \(textHex) !important; }
          </style>
        </head>
        <body>
          <script id="source" type="text/plain">\(escaped)</script>
          <div id="content"></div>
          <script>
            document.addEventListener("DOMContentLoaded", function () {
              const source = document.getElementById("source");
              const content = document.getElementById("content");
              const raw = source ? source.textContent : "";
              if (window.marked) {
                content.innerHTML = marked.parse(raw || "", { breaks: true, gfm: true });
              } else {
                content.textContent = raw || "";
              }
              if (window.renderMathInElement) {
                renderMathInElement(content, {
                  delimiters: [
                    { left: "$$", right: "$$", display: true },
                    { left: "$", right: "$", display: false }
                  ],
                  throwOnError: false
                });
              }
            });
          </script>
        </body>
        </html>
        """
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

// MARK: - Extensions

extension MarkdownUI.Theme {
    // 4. 创建一个根据 ColorScheme 变化的 Theme
    static func adaptiveTheme(colorScheme: ColorScheme) -> MarkdownUI.Theme {
        let base = MarkdownUI.Theme()
            .text {
                ForegroundColor(.primary)
                FontSize(14)
            }
            .code {
                FontFamilyVariant(.monospaced)
                BackgroundColor(.clear) // 清除背景，让 Splash 处理
                // 浅色模式下代码文字用粉色/红色，深色模式用橙色，或者让 Splash 接管
                ForegroundColor(colorScheme == .dark ? .orange : .pink)
            }
            .codeBlock { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(13)
                    }
                    .padding(.vertical, 5)
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.2)) // 适配颜色
                        .frame(width: 3)
                    configuration.label
                        .padding(.leading, 10)
                        .foregroundStyle(.secondary)
                }
            }
            .link {
                ForegroundColor(.blue)
                UnderlineStyle(.single)
            }
        
        return base
    }
}

// MARK: - Splash Highlighter Helper

struct SplashCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    let theme: Splash.Theme

    func highlightCode(_ code: String, language: String?) -> Text {
        let highlighter = Splash.SyntaxHighlighter(format: Splash.AttributedStringOutputFormat(theme: theme))
        return Text(AttributedString(highlighter.highlight(code)))
    }

    // 深色模式 (使用内置的 wwdc17)
    static var wwdc17: Self {
        SplashCodeSyntaxHighlighter(theme: .wwdc17(withFont: .init(size: 13)))
    }
    
    // 浅色模式 (手动定义一个基本浅色主题)
    static var basicLight: Self {
        SplashCodeSyntaxHighlighter(theme: .basicLight(withFont: .init(size: 13)))
    }
}

// 手动扩展 Splash.Theme 来添加浅色主题
extension Splash.Theme {
    static func basicLight(withFont font: Splash.Font) -> Splash.Theme {
        // 1. 定义颜色 (显式指定 alpha 以帮助编译器)
        let plainTextColor = Splash.Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0) // 普通代码为黑色
        
        let keywordColor = Splash.Color(red: 0.6, green: 0.1, blue: 0.4, alpha: 1.0)      // 紫色
        let stringColor = Splash.Color(red: 0.8, green: 0.1, blue: 0.1, alpha: 1.0)       // 红色
        let typeColor = Splash.Color(red: 0.3, green: 0.1, blue: 0.5, alpha: 1.0)         // 深紫色
        let callColor = Splash.Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0)         // 蓝色
        let numberColor = Splash.Color(red: 0.1, green: 0.1, blue: 0.8, alpha: 1.0)       // 深蓝
        let commentColor = Splash.Color(red: 0.4, green: 0.5, blue: 0.4, alpha: 1.0)      // 绿色
        let propertyColor = Splash.Color(red: 0.1, green: 0.5, blue: 0.6, alpha: 1.0)     // 蓝绿色
        let dotAccessColor = Splash.Color(red: 0.3, green: 0.4, blue: 0.1, alpha: 1.0)    // 橄榄色
        let preprocessingColor = Splash.Color(red: 0.5, green: 0.3, blue: 0.1, alpha: 1.0)// 棕色
        
        // 2. 显式定义字典类型，解决 "Contextual type" 错误
        let tokenColors: [Splash.TokenType: Splash.Color] = [
            .keyword: keywordColor,
            .string: stringColor,
            .type: typeColor,
            .call: callColor,
            .number: numberColor,
            .comment: commentColor,
            .property: propertyColor,
            .dotAccess: dotAccessColor,
            .preprocessing: preprocessingColor
        ]
        
        // 3. 正确的初始化方法：font, plainTextColor, tokenColors
        return Splash.Theme(
            font: font,
            plainTextColor: plainTextColor, // 必填：未匹配到的符号（如括号、逗号）的颜色
            tokenColors: tokenColors        // 必填：关键字颜色字典
        )
    }
}
