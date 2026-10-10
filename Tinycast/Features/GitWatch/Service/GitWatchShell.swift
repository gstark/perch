import Foundation

/// Runs a script on a machine through `GitWatchMachine.shellCommand` and returns what it printed.
nonisolated enum GitWatchShell {
    /// The pipe reads and the exit wait block, so they stay off the cooperative pool.
    private static let queue = DispatchQueue(
        label: "com.gstark.perch.git-watch", qos: .utility, attributes: .concurrent)

    static func run(
        _ script: String, on machine: GitWatchMachine, timeout: Duration = .seconds(60)
    ) async -> Result<String, GitWatchFailure> {
        let command = machine.shellCommand
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(filePath: command.executable)
        process.arguments = command.arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        // An ssh that exits before reading stdin would otherwise kill Perch with SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        guard let exit = try? process.runObservingExit() else { return .failure(.launch) }
        let deadline = Task.detached { () -> Bool in
            do { try await Task.sleep(for: timeout) } catch { return false }
            terminate(process)
            return true
        }
        let (stdout, stderr) = await withTaskCancellationHandler {
            try? input.fileHandleForWriting.write(contentsOf: Data(script.utf8))
            try? input.fileHandleForWriting.close()
            async let stdout = readAll(output)
            async let stderr = readAll(errors)
            return await (stdout, stderr)
        } onCancel: {
            terminate(process)
        }
        await blocking { exit.wait() }
        deadline.cancel()
        if await deadline.value { return .failure(.timedOut) }
        guard process.terminationStatus == 0 else {
            return .failure(.exited(message: String(bytes: stderr, encoding: .utf8) ?? ""))
        }
        return .success(String(bytes: stdout, encoding: .utf8) ?? "")
    }

    private static func readAll(_ pipe: Pipe) async -> Data {
        await blocking { (try? pipe.fileHandleForReading.readToEnd()) ?? Data() }
    }

    private static func blocking<Value: Sendable>(
        _ work: @escaping @Sendable () -> Value
    ) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// `terminate()` traps on a process that never launched, so the state has to be asked first.
    private static func terminate(_ process: Process) {
        if process.isRunning { process.terminate() }
    }
}
