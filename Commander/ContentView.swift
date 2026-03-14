import SwiftUI
import MarkdownUI
import Splash
import AppKit
import SwiftTerm

struct ContentView: View {
    @Bindable var appState: AppState
    @FocusState private var isInputFocused: Bool
    @AppStorage(AppStorageKey.multilineInput) private var multilineInput = false
    @State private var inputText: String = ""
    @State private var outputBaseHeight: CGFloat = 360
    @GestureState private var outputDragTranslation: CGFloat = 0
    
    @Environment(\.openSettings) private var openSettings
    // 1. 引入环境变量监听当前的系统外观模式 (Dark/Light)
    @Environment(\.colorScheme) private var colorScheme
    
    private let singleLinePlaceholder = "Type 'help'..."
    private let multilinePlaceholderTop: CGFloat = 4
    private let multilinePlaceholderLeading: CGFloat = 4
    
    private var outputHeight: CGFloat {
        min(max(200, outputBaseHeight + outputDragTranslation), 720)
    }

    private var runningTerminalSessions: [TerminalSessionItem] {
        appState.terminalSessions.filter { $0.isRunning }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // --- 1. 顶部输入区域 ---
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
                            .focused($isInputFocused)
                            .onExitCommand {
                                handleExitCommand()
                            }
                    }
                    .frame(minHeight: 58, maxHeight: 110)
                } else {
                    TextField(singleLinePlaceholder, text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .frame(height: 22)
                        .focused($isInputFocused)
                        .onKeyPress(.return, phases: [.down]) { keyPress in
                            if keyPress.modifiers.contains(.shift) {
                                enterMultilineModeWithNewline()
                                return .handled
                            }

                            submitInput()
                            return .handled
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
                        isInputFocused = true
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
            .padding(.vertical, multilineInput ? 10 : 6)
            // 2. 修改背景色：使用 primary.opacity 让其在黑白模式下都能自动适配
            // 浅色模式下是淡淡的灰，深色模式下是淡淡的白
            .background(Color.primary.opacity(0.05))
            
            // --- 2. 内容展示区域 ---
            if appState.showHistoryView || !runningTerminalSessions.isEmpty || !appState.resultText.isEmpty {
                
                Divider()
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer()
                        Capsule()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 42, height: 5)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .updating($outputDragTranslation) { value, state, _ in
                                state = value.translation.height
                            }
                            .onEnded { value in
                                outputBaseHeight = min(max(200, outputBaseHeight + value.translation.height), 720)
                            }
                    )

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
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if !runningTerminalSessions.isEmpty {
                                Divider()

                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Processes")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.top, 10)

                                    ScrollView {
                                        LazyVStack(alignment: .leading, spacing: 10) {
                                            ForEach(runningTerminalSessions) { session in
                                                terminalSessionCard(session)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.bottom, 12)
                                    }
                                    .frame(maxHeight: 280)
                                }
                                .background(Color.primary.opacity(0.03))
                            }
                        }
                    }
                }
                .frame(height: outputHeight)
            }
        }
        .frame(width: 500)
        .background(.ultraThinMaterial) // 保持毛玻璃效果
        .onAppear {
            inputText = appState.query
            isInputFocused = true
        }
        .onChange(of: inputText) { _, newValue in
            guard !multilineInput else { return }
            if newValue.contains("\n") || newValue.contains("\r") {
                multilineInput = true
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
                    isInputFocused = true
                }
            }
        }
        .onChange(of: appState.shouldOpenSettings) { _, newValue in
            if newValue {
                openSettings()
                appState.shouldOpenSettings = false
            }
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
        appState.query = inputText
        appState.reset()
        inputText = appState.query
    }

    private func enterMultilineModeWithNewline() {
        if !multilineInput {
            multilineInput = true
        }
        inputText += "\n"
        isInputFocused = true
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

            if !session.isCollapsed {
                Divider()

                if session.runInBackground {
                    Text("Background process is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                } else {
                    SwiftTermSessionView(
                        sessionID: session.id,
                        outputData: session.outputData,
                        onSendData: { id, data in
                            appState.sendTerminalData(sessionID: id, data: data)
                        }
                    )
                    .frame(minHeight: 110, maxHeight: 240)
                }
            }
        }
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
    let outputData: Data
    let onSendData: (UUID, Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionID: sessionID, onSendData: onSendData)
    }

    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.configureNativeColors()
        view.terminalDelegate = context.coordinator
        view.optionAsMetaKey = true
        view.allowMouseReporting = true
        view.caretViewTracksFocus = true
        context.coordinator.terminalView = view

        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.focusTerminalFromGesture(_:)))
        view.addGestureRecognizer(click)
        return view
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        context.coordinator.sessionID = sessionID
        context.coordinator.terminalView = nsView
        context.coordinator.requestInitialFocusIfNeeded()
        context.coordinator.apply(outputData: outputData, to: nsView)
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        var sessionID: UUID
        private let onSendData: (UUID, Data) -> Void
        private var consumedLength: Int = 0
        fileprivate weak var terminalView: TerminalView?
        private var hasRequestedInitialFocus = false

        init(sessionID: UUID, onSendData: @escaping (UUID, Data) -> Void) {
            self.sessionID = sessionID
            self.onSendData = onSendData
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

        func apply(outputData: Data, to terminal: TerminalView) {
            if outputData.count < consumedLength {
                consumedLength = 0
                let reset: [UInt8] = [0x1B, 0x63]
                terminal.feed(byteArray: reset[...])
            }

            let total = outputData.count
            guard total > consumedLength else { return }

            let chunk = outputData[consumedLength..<total]
            let bytes = Array(chunk)
            terminal.feed(byteArray: bytes[...])
            consumedLength = total
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {
            guard let url = URL(string: link) else { return }
            NSWorkspace.shared.open(url)
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let payload = Data(data)
            guard !payload.isEmpty else { return }
            onSendData(sessionID, payload)
        }
    }
}
