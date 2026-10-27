import Darwin
import Foundation

/// Reads a process's path, argv, working directory and parent from the kernel.
enum ProcessFactsReader {
    /// Nil when the process is gone or another user's; argv and cwd need the same owner.
    nonisolated static func read(pid: pid_t) -> ProcessFacts? {
        guard let executable = path(of: pid), let arguments = arguments(of: pid) else { return nil }
        return ProcessFacts(
            executable: executable, arguments: arguments,
            workingDirectory: workingDirectory(of: pid), parent: parentName(of: pid))
    }

    private nonisolated static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return string(from: buffer[...])
    }

    /// `KERN_PROCARGS2` is argc, the exec path, NUL padding, then argc NUL-terminated strings.
    private nonisolated static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(bytes: buffer[start..<index], encoding: .utf8) ?? "")
            index += 1
        }
        return arguments
    }

    private nonisolated static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }
        return path.isEmpty ? nil : path
    }

    private nonisolated static func parentName(of pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_ppid > 1 else {
            return nil
        }
        return path(of: pid_t(info.pbi_ppid)).map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    private nonisolated static func string(from buffer: ArraySlice<CChar>) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }
}
