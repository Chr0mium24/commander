import SwiftUI
import MarkdownUI
import Splash
import AppKit
import SwiftTerm

struct ContentView: View {
    private let compactWindowHeight: CGFloat = 40
    private let expandedWindowMinimumHeight: CGFloat = 220

    private enum InputFocusField: Hashable {
        case singleLine
        case multiLine
    }

    @Bindable var appState: AppState
    @FocusState private var focusedInput: InputFocusField?
    @State private var multilineInput = false
    @State private var inputText: String = ""
    @State private var processBaseHeight: CGFloat = 190
    @GestureState private var processDragTranslation: CGFloat = 0
    
    @Environment(\.openSettings) private var openSettings
    // 1. 引入环境变量监听当前的系统外观模式 (Dark/Light)
    @Environment(\.colorScheme) private var colorScheme
    
    private let singleLinePlaceholder = "Type 'help'..."
    private let multilinePlaceholderTop: CGFloat = 4
    private let multilinePlaceholderLeading: CGFloat = 4
    
    private var processMaxHeight: CGFloat {
        420
    }

    private var processHeight: CGFloat {
        min(max(120, processBaseHeight + processDragTranslation), processMaxHeight)
    }

    private var runningTerminalSessions: [TerminalSessionItem] {
        appState.terminalSessions.filter { $0.isRunning }
    }

    private var detectedCodeBlocks: [DetectedCodeBlock] {
        MarkdownCodeBlockExtractor.extract(from: appState.resultText)
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
        hasVisibleHistory || !runningTerminalSessions.isEmpty || appState.isLoading || hasVisibleResultText
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
        .onChange(of: appState.shouldOpenSettings) { _, newValue in
            if newValue {
                openSettings()
                appState.shouldOpenSettings = false
            }
        }
    }

    private var inputSection: some View {
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
                        .onExitCommand {
                            handleMultilineExitCommand()
                        }
                }
                .frame(minHeight: 58, maxHeight: 110)
            } else {
                TextField(singleLinePlaceholder, text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .frame(height: 22)
                    .focused($focusedInput, equals: .singleLine)
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
                    .onExitCommand {
                        handleExitCommand()
                    }
            }

            HStack(spacing: 8) {
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
                                        MarkdownResultView(
                                            resultText: appState.resultText,
                                            colorScheme: colorScheme
                                        )
                                    }
                                }

                                if appState.isAIResponse && !appState.isLoading && !appState.resultText.isEmpty {
                                    Divider()
                                        .padding(.vertical, 8)

                                    HStack(spacing: 12) {
                                        Spacer()
                                        Button(action: {
                                            if let attributed = try? AttributedString(markdown: appState.resultText) {
                                                appState.copyToClipboard(String(attributed.characters))
                                            } else {
                                                appState.copyToClipboard(appState.resultText)
                                            }
                                        }) {
                                            Label("Copy Text", systemImage: "doc.on.doc")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.bordered)

                                        Button(action: {
                                            appState.copyToClipboard(appState.resultText)
                                        }) {
                                            Label("Copy Markdown", systemImage: "text.aligncenter")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }

                                if appState.isAIResponse && !appState.isLoading && !detectedCodeBlocks.isEmpty {
                                    Divider()
                                        .padding(.vertical, 8)

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Code Blocks")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        ForEach(detectedCodeBlocks) { block in
                                            HStack(spacing: 8) {
                                                Text(block.title)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)

                                                Spacer()

                                                Button("Copy Code") {
                                                    appState.copyToClipboard(block.code)
                                                }
                                                .font(.caption)
                                                .buttonStyle(.bordered)

                                                if isRunnableCodeLanguage(block.language) {
                                                    Button("Run") {
                                                        appState.runGeneratedCode(
                                                            language: block.language,
                                                            code: block.code
                                                        )
                                                    }
                                                    .font(.caption)
                                                    .buttonStyle(.borderedProminent)
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(Color.primary.opacity(0.04))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !runningTerminalSessions.isEmpty {
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
                                    .padding(.top, 0)

                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 10) {
                                        ForEach(runningTerminalSessions) { session in
                                            terminalSessionCard(session)
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

        appState.query = normalized
        inputText = normalized
        appState.executeCommand()
    }
    
    private func handleExitCommand() {
        if shouldShowOutputSection {
            appState.collapseToInputOnly()
            inputText = ""
        } else {
            appState.query = inputText
            appState.reset()
            inputText = appState.query
        }
        multilineInput = false
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
    private func terminalSessionCard(_ session: TerminalSessionItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: {
                    appState.toggleTerminalSessionCollapsed(session.id)
                }) {
                    Image(systemName: session.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Text(session.command)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(session.isRunning ? "Running" : "Done")
                    .font(.caption2)
                    .foregroundStyle(session.isRunning ? .orange : .secondary)

                if session.isRunning {
                    Button("Stop") {
                        appState.stopTerminalSession(session.id)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if session.runInBackground {
                if !session.isCollapsed {
                    Divider()
                    Text("Background process is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            } else {
                if !session.isCollapsed {
                    Divider()
                }
                SwiftTermSessionView(
                    sessionID: session.id,
                    command: session.command,
                    onRegisterTerminator: { id, terminate in
                        appState.registerTerminalSessionController(sessionID: id, terminate: terminate)
                    },
                    onProcessTerminated: { id, exitCode, transcript in
                        appState.completeTerminalSession(sessionID: id, exitCode: exitCode, transcript: transcript)
                    }
                )
                .frame(height: session.isCollapsed ? 0 : 170)
                .opacity(session.isCollapsed ? 0 : 1)
                .clipped()
                .allowsHitTesting(!session.isCollapsed)
            }
        }
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct DetectedCodeBlock: Identifiable {
    let id: Int
    let language: String
    let code: String
    let preview: String

    var title: String {
        let languageText = language.isEmpty ? "code" : language
        if preview.isEmpty {
            return languageText
        }
        return "\(languageText): \(preview)"
    }
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

            let firstLine = code.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
            let preview = firstLine.trimmingCharacters(in: .whitespaces)
            let clippedPreview: String
            if preview.count > 46 {
                clippedPreview = String(preview.prefix(46)) + "..."
            } else {
                clippedPreview = preview
            }

            blocks.append(
                DetectedCodeBlock(
                    id: index,
                    language: language,
                    code: code,
                    preview: clippedPreview
                )
            )
        }

        return blocks
    }
}

private struct MarkdownResultView: View, Equatable {
    let resultText: String
    let colorScheme: ColorScheme
    
    static func == (lhs: MarkdownResultView, rhs: MarkdownResultView) -> Bool {
        lhs.resultText == rhs.resultText && lhs.colorScheme == rhs.colorScheme
    }
    
    var body: some View {
        Markdown(resultText)
            .markdownTheme(.adaptiveTheme(colorScheme: colorScheme))
            .markdownCodeSyntaxHighlighter(
                colorScheme == .dark
                    ? SplashCodeSyntaxHighlighter.wwdc17
                    : SplashCodeSyntaxHighlighter.basicLight
            )
            .textSelection(.enabled)
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

private struct SwiftTermSessionView: NSViewRepresentable {
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

        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.focusTerminalFromGesture(_:)))
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
                terminal.send(txt: "\u{03}")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    terminal.terminate()
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
