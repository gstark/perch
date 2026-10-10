import Foundation

/// Runs `GitWatchScript` on one machine and parses what it prints.
nonisolated enum GitWatchScanner {
    /// The pipe reads and the exit wait block, so they stay off the cooperative pool.
    private static let queue = DispatchQueue(
        label: "com.gstark.perch.git-watch", qos: .utility, attributes: .concurrent)

    static func scan(
        _ machine: GitWatchMachine, timeout: Duration = .seconds(60)
    ) async -> Result<GitWatchReport, GitWatchFailure> {
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
            let script = Data(GitWatchScript.make(roots: machine.roots).utf8)
            try? input.fileHandleForWriting.write(contentsOf: script)
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
            let message = String(bytes: stderr, encoding: .utf8)?
                .split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
            return .failure(.exited(message: message))
        }
        return .success(GitWatchReport(parsing: String(bytes: stdout, encoding: .utf8) ?? ""))
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
