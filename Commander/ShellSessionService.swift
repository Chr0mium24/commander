import Foundation
import Darwin
import Dispatch

final class ShellSession {
    private let process: Process
    private let stdinHandle: FileHandle?
    private var ptyMasterFD: Int32?
    private var readSource: DispatchSourceRead?

    private init(process: Process, stdinHandle: FileHandle?, ptyMasterFD: Int32?) {
        self.process = process
        self.stdinHandle = stdinHandle
        self.ptyMasterFD = ptyMasterFD
    }

    static func start(
        command: String,
        runInBackground: Bool,
        currentDirectory: String,
        onOutput: @escaping @MainActor (Data) -> Void,
        onExit: @escaping @MainActor (Int32) -> Void
    ) throws -> ShellSession {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory, isDirectory: true)

        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(existingPath)"
        env["SWIFT_CTX"] = "1"
        process.environment = env

        if runInBackground {
            process.arguments = ["-c", "nohup \(command) > /dev/null 2>&1 &"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice

            try process.run()
            Task { @MainActor in
                onOutput(Data("Background process launched: \(command)\n".utf8))
                onExit(process.terminationStatus)
            }
            return ShellSession(process: process, stdinHandle: nil, ptyMasterFD: nil)
        }

        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate PTY"]
            )
        }

        process.arguments = ["-c", command]
        let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        let masterHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: false)
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle
        process.standardInput = slaveHandle

        do {
            try process.run()
        } catch {
            close(masterFD)
            throw error
        }

        let session = ShellSession(process: process, stdinHandle: masterHandle, ptyMasterFD: masterFD)
        session.startReadLoop(onOutput: onOutput)

        process.terminationHandler = { terminatedProcess in
            Task { @MainActor in
                onExit(terminatedProcess.terminationStatus)
            }
        }

        return session
    }

    private func startReadLoop(onOutput: @escaping @MainActor (Data) -> Void) {
        guard let fd = ptyMasterFD else { return }

        let queue = DispatchQueue(label: "commander.shell.read.\(UUID().uuidString)")
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)

        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return -1 }
                return read(fd, baseAddress, rawBuffer.count)
            }

            if count > 0 {
                let payload = Data(buffer.prefix(Int(count)))
                Task { @MainActor in
                    onOutput(payload)
                }
                return
            }

            source.cancel()
            self.closeMasterFDIfNeeded()
        }

        source.setCancelHandler { [weak self] in
            self?.closeMasterFDIfNeeded()
        }

        readSource = source
        source.resume()
    }

    func sendInput(_ text: String, appendNewline: Bool = true) {
        guard let stdinHandle else { return }
        guard process.isRunning else { return }

        let normalized: String
        if appendNewline {
            normalized = text.hasSuffix("\n") ? text : text + "\n"
        } else {
            normalized = text
        }

        if let data = normalized.data(using: .utf8) {
            stdinHandle.write(data)
        }
    }

    func sendData(_ data: Data) {
        guard let stdinHandle else { return }
        guard process.isRunning else { return }
        guard !data.isEmpty else { return }
        stdinHandle.write(data)
    }

    func terminate() {
        readSource?.cancel()
        readSource = nil

        guard process.isRunning else { return }
        process.interrupt()
        process.terminate()
    }

    private func closeMasterFDIfNeeded() {
        guard let fd = ptyMasterFD else { return }
        close(fd)
        ptyMasterFD = nil
    }
}
