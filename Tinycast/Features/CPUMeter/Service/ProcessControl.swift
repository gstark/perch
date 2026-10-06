import AppKit
import Darwin

/// What the process menu needs to know about one pid, and the two ways to end it.
@MainActor
enum ProcessControl {
    /// An app reads as Finder names it; anything else by its executable, so helpers stay apart.
    static func name(of pid: pid_t) -> String {
        if let app = NSRunningApplication(processIdentifier: pid),
            app.bundleURL != nil, let name = app.localizedName
        {
            return name
        }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            return URL(fileURLWithPath: string(from: path)).lastPathComponent
        }
        var short = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        if proc_name(pid, &short, UInt32(short.count)) > 0 {
            return string(from: short)
        }
        return "Process \(pid)"
    }

    /// The C string up to its terminator; libproc pads the rest of the buffer with zeros.
    private static func string(from buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// A signal to another user's process needs admin rights, which this menu never asks for.
    static func isOwnedByUser(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_uid == getuid()
    }

    /// An app gets the chance to save; anything else gets SIGTERM. False when nothing was sent.
    static func quit(_ pid: pid_t) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid), app.bundleURL != nil {
            return app.terminate()
        }
        return kill(pid, SIGTERM) == 0
    }

    static func forceQuit(_ pid: pid_t) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid), app.bundleURL != nil {
            return app.forceTerminate()
        }
        return kill(pid, SIGKILL) == 0
    }

    static func openActivityMonitor() {
        guard
            let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.ActivityMonitor")
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
