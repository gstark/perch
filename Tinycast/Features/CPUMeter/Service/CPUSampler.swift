import Darwin
import Foundation

/// Samples per-core load and per-process CPU time once a second, off the main actor.
@MainActor
@Observable
final class CPUSampler {
    static let interval = Duration.seconds(1)
    static let processLimit = 10

    private(set) var cores: [CoreLoad] = []
    private(set) var topProcesses: [ProcessUsage] = []
    @ObservationIgnored var onSample: (() -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Everything one tick reads, timed by the clock `proc_pidinfo` reports CPU time in.
    private struct Snapshot: Sendable {
        let cores: [CoreTicks]
        let processes: [ProcessSample]
        let time: UInt64
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            var previous = await Self.read()
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                let current = await Self.read()
                guard let self else { return }
                apply(previous: previous, current: current)
                previous = current
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func apply(previous: Snapshot, current: Snapshot) {
        cores = CPULoad.loads(previous: previous.cores, current: current.cores)
        let earlier = Dictionary(
            previous.processes.map { ($0.pid, $0.cpuTime) }, uniquingKeysWith: { first, _ in first })
        topProcesses = ProcessLoad.top(
            previous: earlier, current: current.processes, elapsed: current.time &- previous.time,
            limit: Self.processLimit)
        onSample?()
    }

    private static func read() async -> Snapshot {
        await Task.detached(priority: .utility) {
            Snapshot(cores: readCoreTicks(), processes: readProcesses(), time: mach_absolute_time())
        }.value
    }

    // MARK: - Kernel reads

    private nonisolated static let host = mach_host_self()

    private nonisolated static func readCoreTicks() -> [CoreTicks] {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard
            host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount)
                == KERN_SUCCESS,
            let info
        else { return [] }
        defer {
            vm_deallocate(
                mach_task_self_, vm_address_t(bitPattern: info),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(coreCount)).map { core in
            func ticks(_ state: Int32) -> UInt32 {
                UInt32(bitPattern: info[core * stride + Int(state)])
            }
            return CoreTicks(
                user: ticks(CPU_STATE_USER), system: ticks(CPU_STATE_SYSTEM),
                idle: ticks(CPU_STATE_IDLE), nice: ticks(CPU_STATE_NICE))
        }
    }

    /// Times come back in Mach absolute units, the same clock `mach_absolute_time` reads.
    private nonisolated static func readProcesses() -> [ProcessSample] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        // Headroom for processes spawned between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let found = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        guard found > 0 else { return [] }
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        return pids.prefix(Int(found)).compactMap { pid in
            guard pid > 0 else { return nil }
            var info = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
            return ProcessSample(pid: pid, cpuTime: info.pti_total_user + info.pti_total_system)
        }
    }
}
