import SwiftUI
import MarkdownUI
import Splash

struct ContentView: View {
    @Bindable var appState: AppState
    @FocusState private var isInputFocused: Bool
    
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部输入区域 (始终显示)
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.secondary)
                
                TextField("Type 'help'...", text: $appState.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isInputFocused)
                    .onSubmit {
                        appState.executeCommand()
                    }
                    // 监听 ESC，触发状态重置（收起窗口）
                    .onExitCommand {
                        appState.reset()
                    }
                
                if appState.isLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .padding()
            // 输入框背景稍微深一点，区分层次
            .background(Color.black.opacity(0.05))
            
            // 2. 内容展示区域 (条件渲染：只有有内容时才存在)
            if appState.showHistoryView || !appState.resultText.isEmpty {
                
                Divider() // 分割线也随内容一起显示/隐藏
                
                VStack(alignment: .leading, spacing: 0) {
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
                                    Markdown(appState.resultText)
                                        .markdownTheme(.transparent)
                                        .markdownCodeSyntaxHighlighter(SplashCodeSyntaxHighlighter.wwdc17)
                                        .textSelection(.enabled)
                                }
                                
                                // B. 底部按钮 (Ask 模式下显示)
                                if appState.isAIResponse && !appState.isLoading {
                                    Divider()
                                        .padding(.vertical, 8)
                                    
                                    HStack(spacing: 12) {
                                        Spacer()
                                        // 复制纯文本
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
                                        
                                        // 复制 Markdown
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
                // 关键修改：给内容区域指定固定高度
                // 当这个视图存在时，窗口高度 = 输入框高度 + 400
                // 当这个视图不存在时，窗口高度 = 输入框高度 (实现收起效果)
                .frame(height: 400)
            }
        }
        // 关键修改：移除高度约束，只约束宽度，让 SwiftUI 根据 VStack 内容自动调整窗口高度
        .frame(width: 500)
        .background(.ultraThinMaterial)
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
                        // 调用 SwiftUI 的环境方法打开设置窗口
                        openSettings()
                        // 重置信号，防止重复触发
                        appState.shouldOpenSettings = false
                    }
                }
    }
}

// ... (Extensions 保持不变)
extension MarkdownUI.Theme {
    static let transparent = MarkdownUI.Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(14)
        }
        .code {
            FontFamilyVariant(.monospaced)
            BackgroundColor(.clear)
            ForegroundColor(.orange)
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
                    .fill(Color.gray.opacity(0.5))
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
}

struct SplashCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    let theme: Splash.Theme

    func highlightCode(_ code: String, language: String?) -> Text {
        let highlighter = Splash.SyntaxHighlighter(format: Splash.AttributedStringOutputFormat(theme: theme))
        return Text(AttributedString(highlighter.highlight(code)))
    }

    static var wwdc17: Self {
        SplashCodeSyntaxHighlighter(theme: .wwdc17(withFont: .init(size: 13)))
    }
}
