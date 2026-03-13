import SwiftUI
import MarkdownUI
import Splash

struct ContentView: View {
    @Bindable var appState: AppState
    @FocusState private var isInputFocused: Bool
    @AppStorage(AppStorageKey.multilineInput) private var multilineInput = false
    @State private var outputBaseHeight: CGFloat = 360
    @GestureState private var outputDragTranslation: CGFloat = 0
    
    @Environment(\.openSettings) private var openSettings
    // 1. 引入环境变量监听当前的系统外观模式 (Dark/Light)
    @Environment(\.colorScheme) private var colorScheme
    
    private var outputHeight: CGFloat {
        min(max(200, outputBaseHeight + outputDragTranslation), 720)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // --- 1. 顶部输入区域 ---
            HStack(alignment: multilineInput ? .top : .center, spacing: 10) {
                Image(systemName: "terminal")
                    .foregroundColor(.secondary)
                
                if multilineInput {
                    ZStack(alignment: .topLeading) {
                        if appState.query.isEmpty {
                            Text("Type here... (Cmd+Enter to send)")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }

                        TextEditor(text: $appState.query)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .focused($isInputFocused)
                            .onExitCommand {
                                appState.reset()
                            }
                    }
                    .frame(minHeight: 62, maxHeight: 110)
                } else {
                    TextField("Type 'help'...", text: $appState.query)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($isInputFocused)
                        .onSubmit {
                            appState.executeCommand()
                        }
                        .onExitCommand {
                            appState.reset()
                        }
                }

                HStack(spacing: 8) {
                    Button(action: {
                        multilineInput.toggle()
                        isInputFocused = true
                    }) {
                        Image(systemName: multilineInput ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    }
                    .buttonStyle(.borderless)
                    .help(multilineInput ? "Switch to single-line input" : "Switch to multi-line input")

                    Button(action: {
                        appState.executeCommand()
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, multilineInput ? 10 : 6)
            // 2. 修改背景色：使用 primary.opacity 让其在黑白模式下都能自动适配
            // 浅色模式下是淡淡的灰，深色模式下是淡淡的白
            .background(Color.primary.opacity(0.05))
            
            // --- 2. 内容展示区域 ---
            if appState.showHistoryView || !appState.resultText.isEmpty {
                
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
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                // A. 文本内容
                                if appState.isLoading && appState.resultText == "Thinking..." {
                                    Text(appState.resultText)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 4)
                                } else {
                                    // 3. 根据当前模式选择代码高亮主题
                                    Markdown(appState.resultText)
                                        .markdownTheme(.adaptiveTheme(colorScheme: colorScheme)) // 使用适配主题
                                        .markdownCodeSyntaxHighlighter(
                                            // 关键点：深色用 wwdc17，浅色用 sundellColors (Splash 自带的浅色主题)
                                            colorScheme == .dark
                                                ? SplashCodeSyntaxHighlighter.wwdc17
                                                : SplashCodeSyntaxHighlighter.basicLight
                                        )
                                        .textSelection(.enabled)
                                }
                                
                                // B. 底部按钮
                                if appState.isAIResponse && !appState.isLoading {
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
                    }
                }
                .frame(height: outputHeight)
            }
        }
        .frame(width: 500)
        .background(.ultraThinMaterial) // 保持毛玻璃效果
        .onAppear { isInputFocused = true }
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
