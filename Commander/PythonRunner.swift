import Foundation

struct PythonRunner {
    
    /// 执行 Python 代码并返回结果（包含标准输出或错误信息）
    /// - Parameter code: 用户输入的 Python 代码
    /// - Returns: 执行结果字符串（未格式化的 Raw String）
    static func run(code: String) async -> String {
        // 1. 获取 Python 路径
        var pythonPath = UserDefaults.standard.string(forKey: AppStorageKey.pythonPath) ?? ""
        if pythonPath.isEmpty { pythonPath = "/usr/bin/python3" }
        
        // 2. 简单的安全检查
        guard FileManager.default.fileExists(atPath: pythonPath) else {
            return "⚠️ Python executable not found at: `\(pythonPath)`\nPlease configure the correct path in Settings."
        }
        
        // 3. 在后台线程执行 Process
        return await Task.detached {
            // 创建临时文件
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("commander_script_\(UUID().uuidString).py")
            
            do {
                // 写入用户代码
                try code.write(to: tempFile, atomically: true, encoding: .utf8)
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: pythonPath)
                
                // 核心逻辑：嵌入式 Python Runner 脚本 (AST 解析)
                let pythonRunnerCode = """
                import ast, sys, traceback
                
                target_file = sys.argv[1]
                
                try:
                    with open(target_file, 'r', encoding='utf-8') as f:
                        source = f.read()
                
                    tree = ast.parse(source)
                    
                    if tree.body and isinstance(tree.body[-1], ast.Expr):
                        last_node = tree.body.pop()
                        context = {}
                        setup_code = compile(tree, filename=target_file, mode='exec')
                        exec(setup_code, context)
                        last_expr = compile(ast.Expression(last_node.value), filename=target_file, mode='eval')
                        result = eval(last_expr, context)
                        if result is not None:
                            print(result)
                    else:
                        code_obj = compile(source, filename=target_file, mode='exec')
                        exec(code_obj, {})
                        
                except Exception:
                    traceback.print_exc()
                """
                
                process.arguments = ["-u", "-c", pythonRunnerCode, tempFile.path]
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                try process.run()
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let outputStr = String(data: outputData, encoding: .utf8) ?? ""
                let errorStr = String(data: errorData, encoding: .utf8) ?? ""
                
                // 清理临时文件
                try? FileManager.default.removeItem(at: tempFile)
                
                var finalOutput = ""
                if !outputStr.isEmpty { finalOutput += outputStr }
                
                if !errorStr.isEmpty {
                    if !finalOutput.isEmpty { finalOutput += "\n\n" }
                    finalOutput += "Error/Stderr:\n\(errorStr)"
                }
                
                if finalOutput.isEmpty { return "Done (No Output)" }
                
                return finalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                
            } catch {
                return "Execution Error: \(error.localizedDescription)"
            }
        }.value
    }
}