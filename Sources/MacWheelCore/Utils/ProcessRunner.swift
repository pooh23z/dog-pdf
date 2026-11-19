import Foundation

public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol ProcessExecuting: Sendable {
    func run(executableURL: URL, arguments: [String]) async throws -> ProcessResult
}

public final class ProcessRunner: ProcessExecuting {
    public init() {}

    public func run(executableURL: URL, arguments: [String]) async throws -> ProcessResult {
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outPipe
        process.standardError = errPipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let outGroup = DispatchGroup()
                let errGroup = DispatchGroup()
                let box = LockedBuffers()

                outGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    box.setStdout(data)
                    outGroup.leave()
                }

                errGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    box.setStderr(data)
                    errGroup.leave()
                }

                process.terminationHandler = { proc in
                    outGroup.wait()
                    errGroup.wait()
                    let stdout = String(data: box.stdout, encoding: .utf8) ?? ""
                    let stderr = String(data: box.stderr, encoding: .utf8) ?? ""
                    continuation.resume(returning: ProcessResult(
                        exitCode: proc.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                }

                do {
                    try process.run()
                } catch {
                    try? outPipe.fileHandleForReading.close()
                    try? errPipe.fileHandleForReading.close()
                    continuation.resume(throwing: WheelError.processFailed("Failed to launch \(executableURL.lastPathComponent): \(error.localizedDescription)"))
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}

private final class LockedBuffers: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var stdout = Data()
    private(set) var stderr = Data()

    func setStdout(_ data: Data) {
        lock.lock()
        stdout = data
        lock.unlock()
    }

    func setStderr(_ data: Data) {
        lock.lock()
        stderr = data
        lock.unlock()
    }
}
