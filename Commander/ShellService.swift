import Foundation

struct ShellService {
    
    /// 智能运行命令：优先查找脚本，否则作为终端命令执行
    /// - Parameters:
    ///   - input: 用户输入的内容（剔除了 run 关键字后的部分），如 "myscript arg1 arg2" 或 "ls -la"
    ///   - scriptDir: 设置中的脚本文件夹路径
    ///   - pythonInterpreter: 设置中的 Python 解释器路径
    static func run(_ input: String) async -> String {
        let scriptDir = UserDefaults.standard.string(forKey: AppStorageKey.scriptDirectory) ?? ""
        let pythonInterpreter = UserDefaults.standard.string(forKey: AppStorageKey.pythonPath) ?? "/usr/bin/python3"
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Error: Empty command" }
        
        // 1. 拆分命令和参数
        // 例如输入: "auto_build release v1.0"
        // cmdName = "auto_build"
        // arguments = "release v1.0"
        let runInBackground = trimmed.hasSuffix("&")
                if runInBackground {
                    // 去掉末尾的 "&"
                    trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                }
        var finalCommand = trimmed
        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        guard let cmdName = parts.first else { return "" }
        let arguments = parts.count > 1 ? parts[1] : ""
        
        // 2. 只有当脚本目录设置了，才尝试查找脚本
        if !scriptDir.isEmpty {
            let fileManager = FileManager.default
            let dirURL = URL(fileURLWithPath: scriptDir)
            
            // 构造潜在的文件路径
            let shPath = dirURL.appendingPathComponent(cmdName + ".sh").path
            let pyPath = dirURL.appendingPathComponent(cmdName + ".py").path
            let exactPath = dirURL.appendingPathComponent(cmdName).path // 无后缀或精确匹配
            
            // --- Case A: 找到 .sh 脚本 ---
            // 逻辑：/bin/bash "path/to/script.sh" arguments
            if fileManager.fileExists(atPath: shPath) {
                finalCommand = "/bin/bash \"\(shPath)\" \(arguments)"
            }
            
            // --- Case B: 找到 .py 脚本 ---
            // 逻辑：[pythonPath] "path/to/script.py" arguments
            if fileManager.fileExists(atPath: pyPath) {
                // 如果设置里的 pythonPath 为空，给一个默认值
                let interpreter = pythonInterpreter.isEmpty ? "/usr/bin/python3" : pythonInterpreter
                finalCommand = "\"\(interpreter)\" \"\(pyPath)\" \(arguments)"
            }
            
            // --- Case C: 找到精确匹配的文件 (比如二进制工具或无后缀脚本) ---
            if fileManager.fileExists(atPath: exactPath) {
                // 直接尝试运行该文件
                finalCommand = "\"\(exactPath)\" \(arguments)"
            }
           
        }
        
        // 3. --- Case D: 没找到脚本，当作普通全局命令 ---
        // 例如: "mpv video.mp4" -> 直接丢进 zsh 执行
        if runInBackground {
                    return await executeBackgroundProcess(command: finalCommand)
                } else {
                    return await executeProcess(command: finalCommand)
                }
    }
    
    // 底层执行器 (保持不变)
    private static func executeProcess(command: String) async -> String {
        return await withCheckedContinuation { continuation in
            let task = Process()
            let pipe = Pipe()
            
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.launchPath = "/bin/zsh"
            
            // 注入环境变量，确保能找到 brew 安装的软件
            var env = ProcessInfo.processInfo.environment
            env["CLICOLOR"] = "1"
            
            let existingPath = env["PATH"] ?? ""
            let newPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(existingPath)"
            env["PATH"] = newPath
            env["SWIFT_CTX"] = "1"
            task.environment = env
            
            // 使用 zsh -c 执行完整命令字符串
            task.arguments = ["-c", command]
            
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                continuation.resume(returning: "Error executing command: \(error.localizedDescription)")
            }
        }
    }
    
    
    private static func executeBackgroundProcess(command: String) async -> String {
            let task = Process()
            
            // 关键点 1: 不要连接 Pipe 到 output，否则会卡住
            // 将输出重定向到 /dev/null，或者你可以选择写到日志文件
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            
            task.launchPath = "/bin/zsh"
            
            var env = ProcessInfo.processInfo.environment
            let existingPath = env["PATH"] ?? ""
            env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(existingPath)"
            task.environment = env
            
            // 关键点 2: 使用 nohup 或 setsid 甚至简单的 & 让它脱离父进程
            // 但 Swift Process 本身如果直接运行并立马结束函数，需要确保子进程不被杀掉。
            // 在 macOS 上，最简单的方法是让 zsh 去处理后台
            task.arguments = ["-c", "nohup \(command) > /dev/null 2>&1 &"]
            
            do {
                try task.run()
                // 关键点 3: 这里不等待 (No waitUntilExit)
                return "🚀 Background process launched: \(command)"
            } catch {
                return "Failed to launch background process: \(error.localizedDescription)"
            }
        }
}
