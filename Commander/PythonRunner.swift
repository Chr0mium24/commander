//
//  PythonRunner.swift
//  Commander
//
//  Created by Chr0mium on 11/22/25.
//

import Foundation

struct PythonRunner {
    
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
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("commander_script_\(UUID().uuidString).py")
            
            do {
                try code.write(to: tempFile, atomically: true, encoding: .utf8)
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: pythonPath)
                
                var env = ProcessInfo.processInfo.environment
                env["PYTHONIOENCODING"] = "utf-8"
                process.environment = env
                
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
                        if tree.body:
                            setup_code = compile(tree, filename=target_file, mode='exec')
                            exec(setup_code, context)
                        last_expr = compile(ast.Expression(last_node.value), filename=target_file, mode='eval')
                        result = eval(last_expr, context)
                        sys.stdout.flush()
                        if result is not None:
                            print(result)
                    else:
                        code_obj = compile(source, filename=target_file, mode='exec')
                        exec(code_obj, {})
                        
                except Exception:
                    sys.stdout.flush()
                    traceback.print_exc()
                """
                
                process.arguments = ["-u", "-c", pythonRunnerCode, tempFile.path]
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                try process.run()
                
                // --- Swift 6 兼容写法 START ---
                
                // 使用 AsyncSequence 并发读取 stdout 和 stderr
                // reduce(into:) 会将字节流收集到 Data 中，完全不需要手动管理 Buffer
                async let outputDataTask = outputPipe.fileHandleForReading.bytes.reduce(into: Data()) { $0.append($1) }
                async let errorDataTask = errorPipe.fileHandleForReading.bytes.reduce(into: Data()) { $0.append($1) }
                
                // 等待两个流读取完毕（这会自动等待直到 Process 关闭管道）
                let (outputData, errorData) = try await (outputDataTask, errorDataTask)
                
                // 此时进程通常已经结束或即将结束
                process.waitUntilExit()
                
                // --- Swift 6 兼容写法 END ---
                
                let outputStr = String(data: outputData, encoding: .utf8) ?? ""
                let errorStr = String(data: errorData, encoding: .utf8) ?? ""
                
                try? FileManager.default.removeItem(at: tempFile)
                
                var finalOutput = ""
                if !outputStr.isEmpty { finalOutput += outputStr }
                
                if !errorStr.isEmpty {
                    if !finalOutput.isEmpty { finalOutput += "\n\n" }
                    finalOutput += "⚠️ Error/Stderr:\n\(errorStr)"
                }
                
                if finalOutput.isEmpty { return "Done (No Output)" }
                
                return finalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                
            } catch {
                return "Execution Error: \(error.localizedDescription)"
            }
        }.value
    }
}
